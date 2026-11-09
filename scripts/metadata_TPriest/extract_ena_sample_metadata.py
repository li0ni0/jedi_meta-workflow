"""
extract_ena_sample_metadata.py

Sample metadata retrieval step: given a table with a Sample_ID column
containing embedded ENA/SRA/DDBJ accessions (e.g. "SAMEA104408598"), pulls 
available metadata from ENA and produces a tab-delimited table with standardised 
columns. 

GEOGRAPHIC GAP-FILLING (Country / Location from coordinates)
-------------------------------------------------------------------
After metadata is retrieved, any sample whose Country or Location is still
blank but which has valid coordinates is filled in using pre-downloaded reference datasets. 
Existing non-missing values are not overwritten.
ENA's composite "Country: Region" format (e.g. "USA: Auburn") is first split
into a clean Country plus a candidate Location.

  Country:  point-in-polygon against Natural Earth admin-0 country boundaries
            (land); if the point is offshore, against Marine Regions' World
            EEZ boundaries. Left blank for the high seas beyond any EEZ.
  Location: nearest GeoNames city/town within CITY_MATCH_RADIUS_KM (a
            distance-based approximation - GeoNames stores points, not city
            polygons); if none is close enough, the Natural Earth admin-1
            (state/province) polygon containing the point.

All reference layers are loaded and validated BEFORE any ENA retrieval
starts, so a missing or mismatched layer stops the script in seconds rather
than after hours of downloading. Use --skip-geo-assignment to disable this
step entirely (Country/Location then stay exactly as retrieved from ENA).

SETUP
-----
    pip install requests pandas numpy python-dateutil geopandas shapely scipy
    bash download_country_and_loc_info.sh -o reference_data   # one-time

(geopandas/shapely/scipy and the reference data are only needed for the
geographic gap-filling step.)

USAGE
-----
    python extract_ena_sample_metadata.py --input samples.tsv --output ena_metadata.tsv \\
        --reference-dir reference_data

RESUMING
--------
Progress is checkpointed to ena_deep_checkpoint.jsonl (one JSON record per
accession, appended as completed). If interrupted, just rerun the same
command - already-completed accessions are skipped automatically.
"""

import argparse
import json
import logging
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
 
import numpy as np
import pandas as pd
 
try:
    import requests
    from dateutil import parser as dateutil_parser
except ImportError:
    print("Missing dependency. Run:\n  pip install requests python-dateutil")
    sys.exit(1)
 
#####
# CONFIG
#####
 
ACCESSION_REGEX = re.compile(r"(SAMEA\d+|SAMN\d+|SAMD\d+|ERS\d+|SRS\d+|DRS\d+)")
 
BULK_BATCH_SIZE = 500
BULK_FIELDS = [
    "accession", "secondary_sample_accession", "sample_alias", "sample_title",
    "collection_date", "country", "lat", "lon", "depth", "altitude",
    "tax_id", "scientific_name", "first_public", "checklist",
]
 
DEEP_FETCH_WORKERS = 6 # concurrent requests for the per-sample XML pass
CHECKPOINT_FILE = Path("ena_deep_checkpoint.jsonl")  # overridden by --checkpoint-file, see main()
CHECKPOINT_EVERY = 200 # flush progress log every N completed
 
MAX_RETRIES = 4
RETRY_BACKOFF_SEC = 4
 
ENA_PORTAL_SEARCH_URL = "https://www.ebi.ac.uk/ena/portal/api/search"
ENA_BROWSER_XML_URL = "https://www.ebi.ac.uk/ena/browser/api/xml/{}"
 
# Synonym lists for matching free-text XML attribute names to our standard
# columns, used only when Pass 1's structured field is empty for that sample.
TARGET_FIELD_SYNONYMS = {
    "Collection_date": ["collection date", "collection_date", "sampling date",
                          "date of collection", "collection-date"],
    "Latitude_degN": ["latitude", "lat", "geographic location (latitude)",
                        "decimal latitude", "geo_loc_lat"],
    "Longitude_degE": ["longitude", "lon", "long", "geographic location (longitude)",
                         "decimal longitude", "geo_loc_lon"],
    "Country": ["country", "geographic location (country and/or sea)", "geo_loc_name"],
    "Location": ["location", "site", "geographic location (region and locality)",
                   "locality"],
    "Depth_below_surface_m": ["depth", "geographic location (depth)"],
    "Elevation_m": ["elevation", "altitude", "geographic location (elevation)"],
    "Temperature_degC": ["temperature", "temp"],
    "Salinity_psu": ["salinity", "salinity psu", "salinity_psu"],
    "Host_age": ["host_age", "host age", "age"],
    "Host_sex": ["host_sex", "host sex", "sex", "gender"],
    "Host_ethnicity": ["ethnicity", "host_ethnicity", "race", "host_race"],
    "Host_weight_kg": ["host_body_weight", "host_weight", "weight", "host_wt"],
    "Host_height_cm": ["host_height", "host_body_height", "height"],
    "Host_BMI": ["host_body_mass_index", "bmi", "host_bmi"],
    "Oxygen": ["oxygen", "dissolved oxygen", "o2", "do"],
    "pH": ["ph", "ph_water", "water ph"],
    "Phosphate": ["phosphate", "po4", "orthophosphate"],
    "Nitrate": ["nitrate", "no3"],
    "DOC": ["doc", "dissolved organic carbon"],
    "POC": ["poc", "particulate organic carbon", "particular organic carbon"],
    "Silicate": ["silicate", "sio4", "sio3", "silicic acid", "reactive silicate",
                   "dissolved silicate", "silicate concentration", "silicate_concentration",
                   "silicate (sio4)", "si(oh)4"],
    "Chlorophyll_a": ["chlorophyll a", "chlorophyll_a", "chlorophyll", "chl a", "chl_a",
                        "chl-a", "chla", "chl", "chlorophyll concentration",
                        "chlorophyll a concentration", "chlorophyll_a_concentration",
                        "total chlorophyll", "chlorophyll-a"],
    "Fluorescence": ["fluorescence", "fluorescence (relative)", "fluorescence_rfu",
                       "fluorescence (rfu)", "fluorescence intensity", "fluor",
                       "chlorophyll fluorescence", "chlorophyll_fluorescence",
                       "fluorometer", "fluorescence (relative units)"],
    "Size_fraction_min": ["sample_size-fraction_lower-threshold"],
    "Size_fraction_max": ["sample_size-fraction_upper-threshold"],
}
COMBINED_LAT_LON_KEYS = ["lat_lon", "lat lon"]
 
# Standardised output format for Collection_date
OUTPUT_DATE_FORMAT = "%d.%m.%Y"
 
# INSDC's standard "missing value" vocabulary (plus common variants) - any
# attribute holding one of these means the value wasn't actually recorded,
# so it should come through as a blank field, not as this placeholder text.
MISSING_VALUE_TERMS = {
    "not collected", "not recorded", "not applicable", "not provided",
    "not available", "missing", "na", "n/a", "none", "unknown",
    "restricted access", "not determined", "not specified",
}
 
# Geographic gap-filling (Country / Location from coordinates) - see docstring.
LAT_COLUMN = "Latitude_degN"
LON_COLUMN = "Longitude_degE"
COUNTRY_COLUMN = "Country"
LOCATION_COLUMN = "Location"

DEFAULT_REFERENCE_DIR = "reference_data"   # overridden by --reference-dir
CITIES_TXT_CANDIDATES = ["cities500.txt", "cities1000.txt", "cities5000.txt"]
CITY_MATCH_RADIUS_KM = 10   # adjust smaller for stricter "within a city" matching

# Candidate field names to try (in order, case-insensitive) for each dataset,
# since Natural Earth/Marine Regions schemas vary slightly between versions.
ADMIN0_NAME_FIELDS = ["ADMIN", "NAME_EN", "NAME", "name"]
ADMIN1_NAME_FIELDS = ["name", "NAME", "woe_name", "name_en"]
EEZ_NAME_FIELDS = ["TERRITORY1", "SOVEREIGN1", "UNION", "GEONAME"]

# Marine Regions' World EEZ zip ships several shapefiles side by side - only the
# polygon layer has the territory/sovereign name fields we need.
NON_POLYGON_SHP_HINTS = ("boundar", "line", "internal", "archipel", "land")

#####################################################

def clean_value(value):
    """Returns None if value is an INSDC missing-value placeholder
    (case/punctuation-insensitive), otherwise returns value unchanged."""
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    normalised = re.sub(r"[_\-]+", " ", text.lower()).strip()
    if normalised in MISSING_VALUE_TERMS:
        return None
    return value
 
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(), logging.FileHandler("ena_metadata_retrieval.log")],
)
log = logging.getLogger(__name__)
 
 
def retry(fn, *args, **kwargs):
    delay = RETRY_BACKOFF_SEC
    last_exc = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            return fn(*args, **kwargs)
        except Exception as e:
            last_exc = e
            time.sleep(delay)
            delay *= 2
    raise last_exc
 
 
def extract_accession(sample_id):
    m = ACCESSION_REGEX.search(str(sample_id))
    return m.group(1) if m else None
 
 
#####
# Pass 1: fast bulk fetch via ENA Portal API
#####
 
def bulk_fetch(accessions):
    """Query ENA Portal API in batches; returns dict accession -> row dict."""
    results = {}
    n_batches = (len(accessions) + BULK_BATCH_SIZE - 1) // BULK_BATCH_SIZE
    for b in range(n_batches):
        lo, hi = b * BULK_BATCH_SIZE, min((b + 1) * BULK_BATCH_SIZE, len(accessions))
        batch = accessions[lo:hi]
        log.info(f"Bulk fetch batch {b+1}/{n_batches} ({len(batch)} accessions)...")
 
        def _query():
            resp = requests.post(
                ENA_PORTAL_SEARCH_URL,
                data={
                    "result": "sample",
                    "query": " OR ".join(f'accession="{a}"' for a in batch),
                    "fields": ",".join(BULK_FIELDS),
                    "format": "json",
                    "limit": 0,
                },
                timeout=60,
            )
            resp.raise_for_status()
            return resp.json() if resp.text.strip() else []
 
        try:
            rows = retry(_query)
        except Exception as e:
            log.error(f"  batch {b+1} failed after retries: {e}")
            continue
        for row in rows:
            acc = row.get("accession")
            if acc:
                results[acc] = row
    log.info(f"Bulk fetch complete: {len(results)}/{len(accessions)} accessions returned data.")
    return results
 
 
#####
# Pass 2: deep per-sample XML fetch
#####

def parse_coordinate(value, axis):
    """normalises a latitude/longitude value of unknown format into signed
    decimal degrees (positive = N/E, negative = S/W). Handles:
      - already-numeric decimal (e.g. 55.6761, or -55.6761)
      - decimal + direction letter (e.g. "55.6761 N", "N55.6761", "55.6761N")
      - degree-minute-second, with or without symbols
        (e.g. "55 40 33.96 N", "55° 40' 33.96\" N", "55d40m33.96sN")
    Returns None (and leaves it for manual review) if nothing matches,
    rather than guessing.
    `axis` is 'lat' or 'lon', used only to validate the expected direction
    letters and value range.
    """
    if value is None:
        return None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
 
    text = str(value).strip()
    if not text:
        return None
 
    pos_letters, neg_letters = ("N", "S") if axis == "lat" else ("E", "W")
 
    # Plain signed decimal, e.g. "55.6761" or "-55.6761"
    m = re.fullmatch(r"[-+]?\d+(\.\d+)?", text)
    if m:
        return float(text)
 
    # Decimal + direction letter, either order, e.g. "55.6761 N" / "N 55.6761" / "55.6761N"
    m = re.fullmatch(
        rf"\s*([{pos_letters}{neg_letters}])?\s*(\d+(?:\.\d+)?)\s*°?\s*([{pos_letters}{neg_letters}])?\s*",
        text, re.IGNORECASE,
    )
    if m and (m.group(1) or m.group(3)):
        direction = (m.group(1) or m.group(3)).upper()
        val = float(m.group(2))
        return -val if direction == neg_letters else val
 
    # Degree-minute-second, with or without ° ' " symbols, e.g.
    # "55 40 33.96 N", "55° 40' 33.96\" N", "55d40m33.96sN"
    m = re.fullmatch(
        rf"\s*(\d+(?:\.\d+)?)\s*(?:°|d|deg)?\s*"
        rf"(\d+(?:\.\d+)?)?\s*(?:'|m|min)?\s*"
        rf"(\d+(?:\.\d+)?)?\s*(?:\"|s|sec)?\s*"
        rf"([{pos_letters}{neg_letters}])\s*",
        text, re.IGNORECASE,
    )
    if m:
        deg = float(m.group(1))
        minutes = float(m.group(2)) if m.group(2) else 0.0
        seconds = float(m.group(3)) if m.group(3) else 0.0
        direction = m.group(4).upper()
        val = deg + minutes / 60 + seconds / 3600
        return -val if direction == neg_letters else val
 
    return None
 
def parse_combined_lat_lon(text):
    """Parses ENA's common combined 'lat_lon' free-text format, e.g.
    '55.6761 N 12.5683 E' or with DMS components on each side."""
    text = str(text).strip()
    # Split into a "lat half" and "lon half" at the first E/W direction
    # letter (which always terminates the latitude portion in ENA's
    # convention), then parse each half independently.
    m = re.match(r"(.+?[NS])\s+(.+?[EW])\s*$", text, re.IGNORECASE)
    if not m:
        return None, None
    lat = parse_coordinate(m.group(1), "lat")
    lon = parse_coordinate(m.group(2), "lon")
    return lat, lon
 
def parse_date(raw):
    """Standardises a free-text collection date into OUTPUT_DATE_FORMAT.
    Handles full dates in many formats (via dateutil) and leaves
    partial dates (year-only, year-month) and unparseable/placeholder
    values ('not collected', 'missing', etc.) as None.
    Returns (formatted_date_or_None, precision) where precision is one of
    'day', 'month', 'year', or 'unresolved'.
    """
    if raw is None:
        return None, "unresolved"
    text = str(raw).strip()
    if not text or text.lower() in ("not collected", "missing", "not applicable", "na", "n/a"):
        return None, "unresolved"
 
    # ENA date range - use the start date, e.g. "2014-06-01/2014-06-12"
    if "/" in text:
        text = text.split("/")[0].strip()
 
    # Year-only, e.g. "2014"
    if re.fullmatch(r"\d{4}", text):
        return None, "year"
    # Year-month, e.g. "2014-06"
    if re.fullmatch(r"\d{4}-\d{2}", text):
        return None, "month"
 
    try:
        dt = dateutil_parser.parse(text, dayfirst=True)
        return dt.strftime(OUTPUT_DATE_FORMAT), "day"
    except Exception:
        return None, "unresolved"
 
def _extract_number_or_midpoint(text):
    """Extracts a number from text, or the midpoint if text expresses a
    range (e.g. '20-29', '20 to 29')."""
    m = re.search(r"(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)", text)
    if m:
        return (float(m.group(1)) + float(m.group(2))) / 2
    m = re.search(r"(\d+(?:\.\d+)?)", text)
    return float(m.group(1)) if m else None
 
def parse_age_years(raw):
    """Standardises an age value (possibly in days/months/years, possibly a
    range) into a single number of years. Assumes years if no unit is
    stated in the text."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text:
        return None
    value = _extract_number_or_midpoint(text)
    if value is None:
        return None
    if re.search(r"\bday", text):
        return value / 365.25
    if re.search(r"\bmonth", text):
        return value / 12.0
    return value  # 'year'/'yr' or no unit stated - assume years
 
def parse_weight_kg(raw):
    """Standardises a weight value (possibly in lb/g/kg) into kilograms.
    Assumes kg if no unit is stated in the text."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text:
        return None
    value = _extract_number_or_midpoint(text)
    if value is None:
        return None
    if re.search(r"\blb\b|\blbs\b|pound", text):
        return value * 0.45359237
    if re.search(r"\bg\b|gram", text) and not re.search(r"\bkg\b|kilogram", text):
        return value / 1000.0
    return value  # 'kg'/'kilogram' or no unit stated - assume kg
 
def parse_height_cm(raw):
    """Standardises a height value (possibly in ft/in, m, or cm) into
    centimeters. Assumes cm if no unit is stated in the text."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text:
        return None
    # Combined feet+inches, e.g. "5'7\"" or "5 ft 7 in"
    m = re.search(r"(\d+)\s*(?:'|ft|feet)\s*(\d+(?:\.\d+)?)?\s*(?:\"|in|inch(?:es)?)?", text)
    if m and ("'" in text or "ft" in text or "feet" in text):
        feet = float(m.group(1))
        inches = float(m.group(2)) if m.group(2) else 0.0
        return feet * 30.48 + inches * 2.54
    value = _extract_number_or_midpoint(text)
    if value is None:
        return None
    if re.search(r"\bcm\b|centimet", text):
        return value
    if re.search(r"\bin\b|inch", text):
        return value * 2.54
    if re.search(r"\bm\b|metre|meter", text):
        return value * 100.0
    return value  # no unit stated - assume cm

def Standardise_sex(raw):
    """normalises host sex values to a consistent Title Case, mapping
    common abbreviations (M/F) to full words."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text:
        return None
    if text in ("m", "male"):
        return "Male"
    if text in ("f", "female"):
        return "Female"
    return text.title()

MOLAR_MASS_G_MOL = {"phosphate": 94.97, "nitrate": 62.00, "carbon": 12.011, "oxygen": 32.00,
                    "silicate": 92.08}  # silicate as SiO4, in line with phosphate (PO4) / nitrate (NO3) above
 
def parse_concentration_mgL(raw, molar_mass):
    """Standardises a nutrient/carbon concentration into mg/L. Handles
    mg/L (as-is), ug/L, umol/L (micromolar), mmol/L (millimolar) via the
    given molar mass, and ppm (treated as approximately equal to mg/L for
    dilute aqueous solutions). Assumes mg/L if no unit is stated."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text:
        return None
    value = _extract_number_or_midpoint(text)
    if value is None:
        return None
    if re.search(r"mg\s*/?\s*l\b|mgl\b", text):
        return value
    if re.search(r"(?:u|µ)g\s*/?\s*l\b", text):
        return value / 1000.0
    if re.search(r"(?:u|µ)mol|micromolar", text):
        return value * molar_mass / 1000.0
    if re.search(r"mmol|millimolar", text):
        return value * molar_mass
    return value  # 'ppm', or no unit stated - assume mg/L
 
def parse_oxygen_mgL(raw):
    """Standardises dissolved oxygen into mg/L. Percent saturation values
    are left unconverted (returns None) since converting %sat to an
    absolute concentration needs temperature and salinity, which aren't
    reliably available here - worth checking these manually if they show
    up often in your data."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text:
        return None
    if re.search(r"%|percent|saturation", text):
        return None
    if re.search(r"ml\s*/?\s*l\b", text):
        value = _extract_number_or_midpoint(text)
        return value * 1.429 if value is not None else None  # standard mL/L -> mg/L factor
    return parse_concentration_mgL(text, MOLAR_MASS_G_MOL["oxygen"])
 
def parse_ph(raw):
    """Extracts a numeric pH value (unitless, no conversion needed)."""
    if raw is None:
        return None
    return _extract_number_or_midpoint(str(raw).strip().lower())
 
def parse_chlorophyll_ugL(raw):
    """Standardises a chlorophyll (a) concentration into ug/L (numerically
    identical to mg/m3). Handles mg/m3, ug/L, ng/L and mg/L. Assumes ug/L if no
    unit is stated. Fluorescence-derived 'chlorophyll' readings in relative
    units (RFU, V) can't be told apart from true concentrations by text alone -
    they would be read as ug/L, so check the raw attributes if that matters."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text:
        return None
    value = _extract_number_or_midpoint(text)
    if value is None:
        return None
    if re.search(r"mg\s*[/.]?\s*m\s*\^?\s*\(?-?3", text):   # mg/m3 == ug/L
        return value
    if re.search(r"(?:u|\u00b5)g\s*[/. ]?\s*l\b", text):
        return value
    if re.search(r"\bng\s*[/. ]?\s*l\b", text):
        return value / 1000.0
    if re.search(r"mg\s*[/. ]?\s*l\b", text):
        return value * 1000.0
    return value  # no unit stated - assume ug/L

def parse_fluorescence(raw):
    """Extracts a numeric fluorescence value (midpoint if a range). Fluorescence
    is reported in submitter-specific relative units (RFU, volts, uncalibrated
    counts...), so NO unit conversion is attempted - values are only comparable
    within a single study. Original text stays available in the raw
    attributes JSON."""
    if raw is None:
        return None
    return _extract_number_or_midpoint(str(raw).strip().lower())

def parse_size_fraction_um(raw):
    """Standardises a filter size-fraction threshold into micrometers.
    If the value is purely text with no number at all (e.g. 'Inf',
    'no prefiltration'), returns None - that indicates no size fraction
    was actually applied, not a real threshold."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text or not re.search(r"\d", text):
        return None
    m = re.search(r"(\d+(?:\.\d+)?)", text)
    if not m:
        return None
    value = float(m.group(1))
    if re.search(r"\bmm\b|millimet", text):
        return value * 1000.0
    if re.search(r"\bnm\b|nanomet", text):
        return value / 1000.0
    return value  # 'um'/'µm'/'micron' or no unit - assume already um
 
def parse_elevation_m(raw):
    """Standardises elevation into meters. Assumes meters if no unit is
    stated in the text."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text or not re.search(r"\d", text):
        return None
    value = _extract_number_or_midpoint(text)
    if value is None:
        return None
    if re.search(r"\bft\b|feet|foot", text):
        return value * 0.3048
    return value  # 'm'/'meter'/'metre' or no unit - assume meters
 
def parse_depth_m(raw):
    """Standardises depth into meters, converting from cm if stated.
    Unlike age/weight/height, a range is preserved AS A RANGE (e.g.
    '10-20') rather than collapsed to a midpoint, per request - returns a
    string for ranges, a float for single values."""
    if raw is None:
        return None
    text = str(raw).strip().lower()
    if not text or not re.search(r"\d", text):
        return None
    unit_factor = 0.01 if re.search(r"\bcm\b|centimet", text) else 1.0  # else 'm'/no unit - assume meters
 
    m = re.search(r"(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)", text)
    if m:
        v1 = float(m.group(1)) * unit_factor
        v2 = float(m.group(2)) * unit_factor
        return f"{v1:g}-{v2:g}"
 
    m = re.search(r"(\d+(?:\.\d+)?)", text)
    if not m:
        return None
    return float(m.group(1)) * unit_factor
 
def fetch_sample_xml(accession):
    """Fetch + parse one sample's full XML record. Returns a dict of
    lowercased-attribute-name -> value, plus '__alias' and '__title'."""
    import xml.etree.ElementTree as ET
 
    def _fetch():
        resp = requests.get(ENA_BROWSER_XML_URL.format(accession), timeout=30)
        resp.raise_for_status()
        return resp.text
 
    xml_text = retry(_fetch)
    root = ET.fromstring(xml_text)
    attrs = {}
    sample_el = root.find(".//SAMPLE")
    if sample_el is not None:
        attrs["__alias"] = sample_el.attrib.get("alias", "")
        title_el = sample_el.find("./TITLE")
        attrs["__title"] = title_el.text if title_el is not None else ""
    for attr_el in root.findall(".//SAMPLE_ATTRIBUTE"):
        tag_el = attr_el.find("TAG")
        val_el = attr_el.find("VALUE")
        if tag_el is not None and val_el is not None and tag_el.text:
            cleaned = clean_value(val_el.text.strip() if val_el.text else "")
            if cleaned is not None:
                attrs[tag_el.text.strip().lower()] = cleaned
    return attrs
 
def match_target_fields(xml_attrs):
    """Best-effort synonym matching of raw XML attributes to standard columns."""
    matched = {}
    for field, synonyms in TARGET_FIELD_SYNONYMS.items():
        for syn in synonyms:
            if syn in xml_attrs and xml_attrs[syn]:
                matched[field] = xml_attrs[syn]
                break
    if "Latitude_degN" in matched:
        matched["Latitude_degN"] = parse_coordinate(matched["Latitude_degN"], "lat")
    if "Longitude_degE" in matched:
        matched["Longitude_degE"] = parse_coordinate(matched["Longitude_degE"], "lon")
    if matched.get("Latitude_degN") is None or matched.get("Longitude_degE") is None:
        for key in COMBINED_LAT_LON_KEYS:
            if key in xml_attrs and xml_attrs[key]:
                lat, lon = parse_combined_lat_lon(xml_attrs[key])
                if lat is not None:
                    matched.setdefault("Latitude_degN", lat)
                    matched.setdefault("Longitude_degE", lon)
                break
    matched["sample_type"] = xml_attrs.get("organism")
    matched["sample_source"] = xml_attrs.get("host") or xml_attrs.get("isolation_source")
    matched["env_broad_scale"] = xml_attrs.get("env_broad_scale") or xml_attrs.get("environment (biome)")
    matched["env_local_scale"] = xml_attrs.get("env_local_scale") or xml_attrs.get("environment (feature)")
    matched["env_medium"] = xml_attrs.get("env_medium") or xml_attrs.get("environment (material)")
    return matched
 
def load_checkpoint():
    done = {}
    if CHECKPOINT_FILE.exists():
        kept_lines = []
        with open(CHECKPOINT_FILE) as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if rec.get("error"):
                    continue
                done[rec["accession"]] = rec
                kept_lines.append(line)
        log.info(f"Resuming: {len(done)} accessions already completed successfully in {CHECKPOINT_FILE} "
                  f"(any previously-failed accessions will be retried).")
    return done
 
def deep_fetch_all(accessions):
    done = load_checkpoint()
    remaining = [a for a in accessions if a not in done]
    log.info(f"Deep fetch: {len(done)} already done, {len(remaining)} remaining.")
 
    if remaining:
        with open(CHECKPOINT_FILE, "a") as ckpt_f, \
             ThreadPoolExecutor(max_workers=DEEP_FETCH_WORKERS) as executor:
            futures = {executor.submit(_deep_fetch_one, acc): acc for acc in remaining}
            n_done = 0
            for future in as_completed(futures):
                acc = futures[future]
                try:
                    rec = future.result()
                except Exception as e:
                    rec = {"accession": acc, "error": str(e)}
                done[acc] = rec
                ckpt_f.write(json.dumps(rec) + "\n")
                n_done += 1
                if n_done % CHECKPOINT_EVERY == 0:
                    ckpt_f.flush()
                    log.info(f"  deep fetch progress: {n_done}/{len(remaining)} this run "
                              f"({len(done)}/{len(accessions)} total).")
    return done
 
 
def _deep_fetch_one(accession):
    xml_attrs = fetch_sample_xml(accession)
    return {"accession": accession, "raw_attributes": xml_attrs}
 
 
#####
# Geographic gap-filling: Country / Location from coordinates (offline)
#####

class GeoReferenceError(Exception):
    pass


def _import_geo_dependencies():
    """Imported lazily so the rest of the script works without geopandas
    installed when --skip-geo-assignment is used."""
    try:
        import geopandas as gpd
        from shapely.geometry import Point
        from scipy.spatial import cKDTree
    except ImportError:
        log.error("Geographic gap-filling needs extra packages. Run:\n"
                  "  pip install geopandas shapely scipy\n"
                  "(or rerun with --skip-geo-assignment to leave Country/Location as "
                  "retrieved from ENA).")
        raise SystemExit(1)
    return gpd, Point, cKDTree


def find_shapefile(directory):
    shp_files = sorted(Path(directory).rglob("*.shp"))
    if not shp_files:
        return None
    preferred = [f for f in shp_files
                 if not any(h in f.stem.lower() for h in NON_POLYGON_SHP_HINTS)]
    return (preferred or shp_files)[0]


def first_present_field(gdf, candidates):
    """Returns the actual column name in gdf matching the first candidate,
    compared case-insensitively (Natural Earth uses UPPERCASE names, while
    Marine Regions' WFS shapefile export uses lowercase, e.g. 'territory1')."""
    lookup = {str(col).lower(): col for col in gdf.columns}
    for c in candidates:
        if c.lower() in lookup:
            return lookup[c.lower()]
    return None


def load_polygon_layer(directory, name_candidates, label):
    gpd, _, _ = _import_geo_dependencies()
    shp = find_shapefile(directory)
    if shp is None:
        raise GeoReferenceError(f"{label}: no shapefile (.shp) found under {directory}")
    gdf = gpd.read_file(shp)
    if gdf.crs is None or gdf.crs.to_epsg() != 4326:
        gdf = gdf.to_crs(epsg=4326)
    field = first_present_field(gdf, name_candidates)
    if field is None:
        raise GeoReferenceError(f"{label}: none of the expected name fields {name_candidates} "
                                f"found in {shp.name}. Actual columns: {gdf.columns.tolist()}. "
                                f"Update the *_NAME_FIELDS constants at the top of this script.")
    log.info(f"{label}: loaded {len(gdf)} polygons, using name field '{field}'.")
    return gdf, field


def load_cities_gazetteer(ref_dir):
    for fname in CITIES_TXT_CANDIDATES:
        path = ref_dir / fname
        if path.exists():
            cols = ["geonameid", "name", "asciiname", "alternatenames", "latitude", "longitude",
                    "feature_class", "feature_code", "country_code", "cc2", "admin1_code",
                    "admin2_code", "admin3_code", "admin4_code", "population", "elevation",
                    "dem", "timezone", "modification_date"]
            df = pd.read_csv(path, sep="\t", header=None, names=cols, quoting=3,
                             encoding="utf-8", low_memory=False)
            log.info(f"Loaded {len(df)} places from {fname}.")
            return df
    raise GeoReferenceError(f"GeoNames cities file: none of {CITIES_TXT_CANDIDATES} found in {ref_dir}")


def haversine_km(lat1, lon1, lat2, lon2):
    r = 6371.0
    lat1, lon1, lat2, lon2 = map(np.radians, [lat1, lon1, lat2, lon2])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    a = np.sin(dlat / 2) ** 2 + np.cos(lat1) * np.cos(lat2) * np.sin(dlon / 2) ** 2
    return 2 * r * np.arcsin(np.sqrt(a))


def to_ecef(lat, lon):
    lat_r, lon_r = np.radians(lat), np.radians(lon)
    x = np.cos(lat_r) * np.cos(lon_r)
    y = np.cos(lat_r) * np.sin(lon_r)
    z = np.sin(lat_r)
    return np.column_stack([x, y, z])


def load_geo_reference(reference_dir):
    """Loads and validates ALL reference layers up front, so a missing or
    mismatched layer stops the script in seconds rather than after hours of
    ENA retrieval. Returns a dict used by assign_country_and_location()."""
    _, _, cKDTree = _import_geo_dependencies()
    ref_dir = Path(reference_dir or DEFAULT_REFERENCE_DIR)
    log.info(f"Geographic gap-filling enabled - loading reference data from {ref_dir}")
    if not ref_dir.is_dir():
        log.error(f"Reference data directory not found: {ref_dir}. Run "
                  f"download_country_and_loc_info.sh -o <dir> and pass that directory via "
                  f"--reference-dir, or rerun with --skip-geo-assignment.")
        raise SystemExit(1)

    problems, ref = [], {}
    for key, subdir, fields, label in (
        ("admin0", "ne_admin0", ADMIN0_NAME_FIELDS, "Admin-0 countries"),
        ("admin1", "ne_admin1", ADMIN1_NAME_FIELDS, "Admin-1 states/provinces"),
        ("eez", "world_eez", EEZ_NAME_FIELDS, "World EEZ"),
    ):
        try:
            ref[key] = load_polygon_layer(ref_dir / subdir, fields, label)
        except GeoReferenceError as e:
            problems.append(str(e))
    try:
        cities = load_cities_gazetteer(ref_dir)
        ref["city_names"] = cities["name"].to_numpy(dtype=object)
        ref["city_lat"] = cities["latitude"].to_numpy(dtype=float)
        ref["city_lon"] = cities["longitude"].to_numpy(dtype=float)
        ref["city_tree"] = cKDTree(to_ecef(ref["city_lat"], ref["city_lon"]))
    except GeoReferenceError as e:
        problems.append(str(e))

    if problems:
        for p in problems:
            log.error(f"  {p}")
        log.error("Incomplete geographic reference data (see above). Re-run "
                  "download_country_and_loc_info.sh (it prints manual-download instructions "
                  "for any layer that fails), or rerun with --skip-geo-assignment.")
        raise SystemExit(1)
    return ref


def spatial_join_names(points_df, lat_col, lon_col, layer):
    """Point-in-polygon lookup; returns a Series of names aligned to
    points_df.index (NaN where no polygon matched). `layer` is a
    (GeoDataFrame, name_field) tuple."""
    gpd, Point, _ = _import_geo_dependencies()
    polygon_gdf, name_field = layer
    geometry = [Point(lon, lat) for lat, lon in zip(points_df[lat_col], points_df[lon_col])]
    pts_gdf = gpd.GeoDataFrame(points_df.copy(), geometry=geometry, crs="EPSG:4326")
    polys = polygon_gdf[[name_field, "geometry"]]
    try:
        joined = gpd.sjoin(pts_gdf, polys, how="left", predicate="intersects")
    except TypeError:
        # geopandas < 0.10 uses 'op' instead of 'predicate'
        joined = gpd.sjoin(pts_gdf, polys, how="left", op="intersects")
    # sjoin can produce duplicate rows if polygons overlap slightly at
    # boundaries - keep the first match per original point.
    joined = joined[~joined.index.duplicated(keep="first")]
    return joined[name_field]


def nearest_city_names(points_df, lat_col, lon_col, ref, radius_km):
    lats = points_df[lat_col].to_numpy(dtype=float)
    lons = points_df[lon_col].to_numpy(dtype=float)
    _, idx = ref["city_tree"].query(to_ecef(lats, lons), k=1)
    d_km = haversine_km(lats, lons, ref["city_lat"][idx], ref["city_lon"][idx])
    names = np.where(d_km <= radius_km, ref["city_names"][idx], np.nan)
    return pd.Series(names, index=points_df.index, dtype=object)


def assign_country_and_location(df, ref):
    """Fills missing Country / Location in `df` (one row per sample, unique
    index) from Latitude_degN / Longitude_degE. Existing non-missing values are
    never overwritten. See the module docstring for the method."""
    df = df.copy()
    for col in (COUNTRY_COLUMN, LOCATION_COLUMN):
        if col not in df.columns:
            df[col] = np.nan
        df[col] = df[col].astype(object)

    lat_numeric = pd.to_numeric(df[LAT_COLUMN], errors="coerce")
    lon_numeric = pd.to_numeric(df[LON_COLUMN], errors="coerce")
    coords_valid = (
        lat_numeric.notna() & lon_numeric.notna()
        & lat_numeric.between(-90, 90) & lon_numeric.between(-180, 180)
    )

    def is_missing(col):
        return df[col].isna() | df[col].astype(str).str.strip().eq("")

    def coords_of(mask):
        return pd.DataFrame({"lat": lat_numeric.loc[mask], "lon": lon_numeric.loc[mask]})

    # ENA's own 'country' field often comes as a composite "Country: Region"
    # string (e.g. "USA: Auburn") - split that into a clean Country and a
    # candidate Location value BEFORE the missing-value fill logic below.
    has_colon = df[COUNTRY_COLUMN].astype(str).str.contains(":", na=False)
    if has_colon.any():
        split = df.loc[has_colon, COUNTRY_COLUMN].astype(str).str.split(":", n=1, expand=True)
        df.loc[has_colon, COUNTRY_COLUMN] = split[0].str.strip()
        location_part = split[1].str.strip()
        still_missing_location = has_colon & is_missing(LOCATION_COLUMN)
        df.loc[still_missing_location, LOCATION_COLUMN] = location_part.loc[still_missing_location]
        log.info(f"Split {has_colon.sum()} composite 'Country: Region' values; "
                 f"{still_missing_location.sum()} of those also had their Location filled "
                 f"from the region part (existing Location values were left untouched).")

    # ---- Country: land (admin-0), then marine (EEZ) ----
    missing_country = is_missing(COUNTRY_COLUMN) & coords_valid
    log.info(f"{missing_country.sum()} samples are missing {COUNTRY_COLUMN} and have valid coordinates.")
    if missing_country.any():
        df.loc[missing_country, COUNTRY_COLUMN] = spatial_join_names(
            coords_of(missing_country), "lat", "lon", ref["admin0"])
        still_missing = missing_country & is_missing(COUNTRY_COLUMN)
        if still_missing.any():
            df.loc[still_missing, COUNTRY_COLUMN] = spatial_join_names(
                coords_of(still_missing), "lat", "lon", ref["eez"])
        unresolved = missing_country & is_missing(COUNTRY_COLUMN)
        log.info(f"Country: filled {missing_country.sum() - unresolved.sum()} / {missing_country.sum()}. "
                 f"{unresolved.sum()} remain unresolved (likely high seas beyond any EEZ).")

    # ---- Location: nearest GeoNames city/town, then admin-1 fallback ----
    missing_location = is_missing(LOCATION_COLUMN) & coords_valid
    log.info(f"{missing_location.sum()} samples are missing {LOCATION_COLUMN} and have valid coordinates.")
    if missing_location.any():
        df.loc[missing_location, LOCATION_COLUMN] = nearest_city_names(
            coords_of(missing_location), "lat", "lon", ref, CITY_MATCH_RADIUS_KM)
        still_missing = missing_location & is_missing(LOCATION_COLUMN)
        if still_missing.any():
            df.loc[still_missing, LOCATION_COLUMN] = spatial_join_names(
                coords_of(still_missing), "lat", "lon", ref["admin1"])
        unresolved = missing_location & is_missing(LOCATION_COLUMN)
        log.info(f"Location: filled {missing_location.sum() - unresolved.sum()} / {missing_location.sum()}. "
                 f"{unresolved.sum()} remain unresolved.")
    return df


#####
# Main
#####
 
def main(input_path, output_path, sample_column, checkpoint_file=None,
         reference_dir=None, skip_geo=False):
    if checkpoint_file:
        global CHECKPOINT_FILE
        CHECKPOINT_FILE = Path(checkpoint_file)
    log.info(f"Using checkpoint file: {CHECKPOINT_FILE}")
    log.info(f"Loading {input_path}")
    try:
        df = pd.read_csv(input_path, sep="\t", encoding="utf-8")
    except UnicodeDecodeError:
        df = pd.read_csv(input_path, sep="\t", encoding="latin-1")
    df.columns = df.columns.str.strip()

    # Fallback: not tab-delimited (e.g. comma/semicolon)? Let pandas sniff it.
    if sample_column not in df.columns:
        try:
            df = pd.read_csv(input_path, sep=None, engine="python")
            df.columns = df.columns.str.strip()
        except Exception:
            pass

    if sample_column not in df.columns:
        log.error(f"Column '{sample_column}' not found. Columns present: {df.columns.tolist()}")
        raise SystemExit("Use --sample-column to name the column containing your sample accessions.")
 
    df["__accession"] = df[sample_column].apply(extract_accession)
    n_no_accession = df["__accession"].isna().sum()
    if n_no_accession:
        log.warning(f"{n_no_accession} row(s) had no extractable accession - these will be skipped.")
 
    accessions = sorted(df["__accession"].dropna().unique().tolist())
    log.info(f"{len(accessions)} unique accessions to retrieve out of {len(df)} rows.")

    # Validate geographic reference data NOW (fail fast), before the slow ENA retrieval.
    geo_ref = None
    if skip_geo:
        log.info("--skip-geo-assignment set: Country/Location will stay as retrieved from ENA.")
    else:
        geo_ref = load_geo_reference(reference_dir)
 
    log.info("=== Pass 1: bulk structured fetch ===")
    bulk_results = bulk_fetch(accessions)
 
    log.info("=== Pass 2: deep per-sample XML fetch (all samples, resumable) ===")
    deep_results = deep_fetch_all(accessions)
 
    log.info("Merging Pass 1 + Pass 2 results...")
    records = []
    all_raw_attrs = {}
    for acc in accessions:
        bulk_row = bulk_results.get(acc, {})
        deep_row = deep_results.get(acc, {})
        raw_attrs = deep_row.get("raw_attributes", {})
        matched = match_target_fields(raw_attrs)
 
        rec = {"Accession": acc,
               "Sample_type": matched.get("sample_type"),
               "Sample_source": matched.get("sample_source")}
        raw_date = clean_value(bulk_row.get("collection_date")) or matched.get("Collection_date")
        formatted_date, _precision = parse_date(raw_date)
        rec["Collection_date"] = formatted_date
 
        raw_lat = clean_value(bulk_row.get("lat"))
        raw_lon = clean_value(bulk_row.get("lon"))
        lat = parse_coordinate(raw_lat, "lat") if raw_lat is not None else matched.get("Latitude_degN")
        lon = parse_coordinate(raw_lon, "lon") if raw_lon is not None else matched.get("Longitude_degE")
        rec["Latitude_degN"] = lat
        rec["Longitude_degE"] = lon
 
        rec["Country"] = clean_value(bulk_row.get("country")) or matched.get("Country")
        rec["Location"] = matched.get("Location")
        rec["Depth_below_surface_m"] = parse_depth_m(clean_value(bulk_row.get("depth")) or matched.get("Depth_below_surface_m"))
        rec["Elevation_m"] = parse_elevation_m(clean_value(bulk_row.get("altitude")) or matched.get("Elevation_m"))
        rec["Temperature_degC"] = matched.get("Temperature_degC")
        rec["Salinity_psu"] = matched.get("Salinity_psu")
        rec["Host_age_years"] = parse_age_years(matched.get("Host_age"))
        rec["Host_sex"] = Standardise_sex(matched.get("Host_sex"))
        rec["Host_ethnicity"] = matched.get("Host_ethnicity")
        rec["Host_weight_kg"] = parse_weight_kg(matched.get("Host_weight_kg"))
        rec["Host_height_cm"] = parse_height_cm(matched.get("Host_height_cm"))
        rec["Host_BMI"] = matched.get("Host_BMI")
        rec["Oxygen_mgL"] = parse_oxygen_mgL(matched.get("Oxygen"))
        rec["pH"] = parse_ph(matched.get("pH"))
        rec["Phosphate_mgL"] = parse_concentration_mgL(matched.get("Phosphate"), MOLAR_MASS_G_MOL["phosphate"])
        rec["Nitrate_mgL"] = parse_concentration_mgL(matched.get("Nitrate"), MOLAR_MASS_G_MOL["nitrate"])
        rec["DOC_mgL"] = parse_concentration_mgL(matched.get("DOC"), MOLAR_MASS_G_MOL["carbon"])
        rec["POC_mgL"] = parse_concentration_mgL(matched.get("POC"), MOLAR_MASS_G_MOL["carbon"])
        rec["Silicate_mgL"] = parse_concentration_mgL(matched.get("Silicate"), MOLAR_MASS_G_MOL["silicate"])
        rec["Chlorophyll_a_ugL"] = parse_chlorophyll_ugL(matched.get("Chlorophyll_a"))
        rec["Fluorescence"] = parse_fluorescence(matched.get("Fluorescence"))
        rec["Size_fraction_min_microm"] = parse_size_fraction_um(matched.get("Size_fraction_min"))
        rec["Size_fraction_max_microm"] = parse_size_fraction_um(matched.get("Size_fraction_max"))
        rec["ENA_env_broad_scale"] = matched.get("env_broad_scale")
        rec["ENA_env_local_scale"] = matched.get("env_local_scale")
        rec["ENA_env_medium"] = matched.get("env_medium")
        rec["ENA_sample_alias"] = bulk_row.get("sample_alias") or raw_attrs.get("__alias")
        rec["ENA_sample_title"] = bulk_row.get("sample_title") or raw_attrs.get("__title")
        all_raw_attrs[acc] = raw_attrs
        records.append(rec)
 
    ena_df = pd.DataFrame(records)
    if geo_ref is not None:
        log.info("=== Geographic gap-filling (Country / Location from coordinates) ===")
        ena_df = assign_country_and_location(ena_df, geo_ref)
    merged = df.merge(ena_df, left_on="__accession", right_on="Accession", how="left")
    merged = merged.drop(columns=["__accession"])
    merged.to_csv(output_path, index=False, sep="\t")
 
    raw_attrs_path = str(Path(output_path).with_suffix("")) + "_raw_attributes.json"
    with open(raw_attrs_path, "w") as f:
        json.dump(all_raw_attrs, f)
    log.info(f"Raw ENA attributes for all samples saved separately to {raw_attrs_path} "
             f"(keyed by accession) - not included in the main table.")
 
    n_with_latlon = merged["Latitude_degN"].notna().sum()
    n_with_date = merged["Collection_date"].notna().sum()
    log.info(f"Done. {len(merged)} rows written to {output_path}.")
    log.info(f"  Latitude/Longitude populated for {n_with_latlon}/{len(merged)} rows.")
    log.info(f"  Collection_date populated for {n_with_date}/{len(merged)} rows.")
    n_errors = sum(1 for r in deep_results.values() if r.get("error"))
    if n_errors:
        log.warning(f"  {n_errors} accession(s) had a deep-fetch error - check "
                    f"{CHECKPOINT_FILE} entries with an 'error' key, then rerun "
                    f"this script (checkpoint will retry only those).")
 
 
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Retrieves full ENA/SRA/DDBJ sample metadata (collection date, "
                     "coordinates, host/environment attributes, etc.) for every sample "
                     "specified in an input table. See the top of this script for full "
                     "documentation of the two-pass design and output columns.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--input", required=True,
                         help="Tab-delimited input table. Must contain a column with ENA "
                              "sample accessions (see --sample-column). It can also contain "
                              "other columns, which will be ignored and not carried over to "
                              "the output. ENA/SRA/DDBJ sample accession (SAMEA/SAMN/SAMD/ERS/SRS/DRS "
                              "followed by digits). Note that the accession doesn't need to "
                              "be the *only* content of that field, it can also be embedded in "
                              "a string. E.g. Both 'SAMEA104408598' (the accession "
                              "alone) and 'MyStudy1_SAMEA104408598' (accession "
                              "embedded in a longer ID you've built yourself) work. "
                              "Any other columns in your table (your own sample IDs, study "
                              "identifiers, notes, anything) are left completely "
                              "untouched and carried through to the output as-is.")
    parser.add_argument("--output", required=True,
                         help="Path to write the output table (tab-delimited). The "
                              "original columns, unchanged, plus one row's worth of "
                              "retrieved ENA metadata appended for "
                              "every row whose Sample_ID yielded an accession. Rows where "
                              "no accession could be extracted are kept in the output with "
                              "the metadata columns left blank. A second file, "
                              "(see --checkpoint-file) is also written alongside "
                              "it, containing every attribute ENA had for each sample "
                              "verbatim (keyed by accession).")
    parser.add_argument("--sample-column", default="Sample_ID",
                         help="Name of column containing ENA/SRA/DDBJ sample accession "
                              "(SAMEA/SAMN/SAMD/ERS/SRS/DRS followed by digits). Note that "
                              "the sample accession can also be embedded within a longer string"
                              "(default = Sample_ID).")
    parser.add_argument("--checkpoint-file", default=None,
                         help="Where to store the resumable deep-fetch checkpoint.")
    parser.add_argument("--reference-dir", default=None,
                         help="Directory containing the reference data downloaded by "
                              "download_country_and_loc_info.sh (ne_admin0/, ne_admin1/, "
                              "world_eez/, cities500.txt), used to fill missing Country/"
                              "Location from coordinates. Pass the same --output_dir you "
                              "gave that script (default: ./reference_data in the current "
                              "directory).")
    parser.add_argument("--skip-geo-assignment", action="store_true",
                         help="Skip the offline Country/Location gap-filling step; the two "
                              "columns then contain only what ENA provided.")
    args = parser.parse_args()
    main(args.input, args.output, args.sample_column, args.checkpoint_file,
         args.reference_dir, args.skip_geo_assignment)