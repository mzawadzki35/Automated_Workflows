# My scientific product

Name:

Normalized Difference Moisture Index (NDMI) for Las Wolski, Kraków.

Scientific question:

What is the spatial distribution of vegetation moisture-related spectral response within the selected area of Las Wolski, Kraków, based on Sentinel-2 Level-2A imagery acquired on 5 June 2025?

Product name, method/equation and authoritative source:

Product: Normalized Difference Moisture Index (NDMI).

Equation:


NDMI = (NIR-SWIR1)/(NIR+SWIR1)


The implementation uses a small epsilon threshold to reject pixels where the denominator is too close to zero.

Authoritative reference:

USGS – Normalized Difference Moisture Index:
https://www.usgs.gov/landsat-missions/normalized-difference-moisture-index

Required bands and why they measure the relevant property:

nir08 – near-infrared reflectance. Vegetation strongly reflects near-infrared radiation, making this band useful for characterising vegetation structure and condition.

swir16 – short-wave infrared reflectance. SWIR reflectance is sensitive to vegetation water content, which makes it useful for moisture-related spectral assessment.

The contrast between NIR and SWIR reflectance provides the basis for NDMI.

AOI name(s), exact bbox(es), and reason for selecting them:

AOI name: Las Wolski, Kraków, Poland.

Bounding box (longitude/latitude):

[19.84, 50.04, 19.87, 50.06]

The area was selected as a forested study site suitable for analysing vegetation-related spectral properties using Sentinel-2 data.


Acquisition IDs and dates; why these dates are appropriate:

Source item ID: S2C_T34UDA_20250605T095638_L2A

Acquisition date: 5 June 2025

Product level: Sentinel-2 Level-2A

The acquisition provides surface reflectance data suitable for multispectral index calculation. The June date represents the vegetation growing season, when the forest canopy is developed and moisture-related vegetation signals can be investigated.


Preparation choices: calibration source, target grid, SCL exclusions, domain restrictions:

Calibration source: Sentinel-2 Level-2A surface reflectance data.

Target CRS: EPSG:32634 (UTM zone 34N).

Target resolution: 20 m.

Reflectance resampling: average, requiring at least 0.999 valid source fraction.

SCL resampling: nearest neighbour.

Cloud and invalid-pixel masking: based on the Scene Classification Layer (SCL).

Excluded SCL classes: [0, 1, 2, 3, 7, 8, 9, 10, 11].

Valid pixels are restricted to the selected AOI and pixels passing the preparation and product validity checks.

The NDMI nominal domain is [-1, 1].



Output layers, metric(s), and their units:

Output layers:

index.tif – NDMI raster.

valid_mask.tif – valid-pixel mask.

receipt.json – processing metadata and quality metrics.

Output grid:

CRS: EPSG:32634

Resolution: 20 × 20 m

Dimensions: 110 × 114 pixels

Metrics:

Mean NDMI: 0.3621 (dimensionless).

Minimum NDMI: -0.2083 (dimensionless).

Maximum NDMI: 0.5577 (dimensionless).

Valid pixels: 11,751.

Valid pixel fraction: approximately 98.39%.

Pixel area: 400 m².

NDMI is a dimensionless index; it is not expressed in physical moisture units.


One scientifically meaningful parameter to vary:

The SCL exclusion policy is a meaningful parameter to vary. For example, the treatment of SCL class 7 (low-probability cloud / unclassified) could be changed and the resulting valid coverage and mean NDMI compared.

Another possible experiment is to compare acquisitions from different dates while keeping the AOI, grid and processing configuration consistent.


What observation or reference could reveal a wrong implementation?

An independent pixel-level calculation using the original NIR and SWIR reflectance values can reveal an incorrect implementation.

For each valid pixel, the expected result is:


NDMI = (NIR-SWIR1)/(NIR+SWIR1)


The independently calculated values should match the output raster within floating-point precision.

The theoretical range [-1, 1] provides an additional sanity check. A reference NDMI product generated independently from the same input scene could provide a further comparison.



Main limitation or confounding factor:

NDMI is an indirect spectral indicator and does not measure actual soil moisture or plant water content directly. Its values can be influenced by canopy structure, vegetation density, shadows, mixed pixels, atmospheric effects and land-cover differences.

Additionally, the selected AOI contained no SCL cloud pixels in classes 8, 9 or 10. Therefore, cloud masking against actual clouds could not be fully tested in this scene.

