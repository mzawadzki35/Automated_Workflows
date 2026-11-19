# Lab 06 investigation

Name and package version: Mikołaj Zawadzki, eo_processing 1.0.0

## Common exercise

Expected requests, first-run attempts, second-run attempts:

- Expected requests: 6
- First run created: 6 attempts (all complete)
- Second run created: 0 attempts

Why six requests are not six acquisition dates:

The six requests are the combinations of 3 acquisition dates (4, 5 and 10 June 2025) and 2 AOIs (river and east). A request is defined by one scene, one AOI, one product and its settings, so each date produces two requests, one per AOI. Six requests therefore represent three dates, each observed over two areas.
How a third input band enters the processing interface:
Only the product declaration changes. In the product class, `required_bands` lists three band roles instead of two, and `calculate` uses `bands["..."]` for the third one. The third band must also be acquired and registered (added to the acquisition config), because `planning.find_inputs` looks up one registered artifact for every required band plus `scl`. The rest of the pipeline already handles it: `preparation.prepare` loops over `required_bands` to calibrate, mask and align each band to the common grid, and `runner.execute` passes the prepared bands to `product.calculate` and writes every declared output role. No change to the shared core is needed.

Cloudy/clear river comparison: raw coverage, usable coverage, candidate water area:

River, 4 June (cloudy): raw coverage 100.0%, usable coverage 47.6%, candidate water 0.1300 km² within 2.2708 km² observed.
River, 5 June (clear): raw coverage 100.0%, usable coverage 99.4%, candidate water 0.2312 km² within 4.7416 km² observed.

The larger water area on 5 June is not evidence of a real change in water extent. The two dates observed different sets of pixels: on 4 June cloud screening removed more than half of the AOI, so less of the river was visible. Raw coverage is 100% on both dates because it only checks missing data, not clouds. The observed area grew about 2.1 times while candidate water grew about 1.8 times, so the water share of the observed area did not rise (about 5.7% vs 4.9%). A fair comparison needs the common valid area (pixels usable on both dates), or at least the same set of pixels on both dates.

Fair comparison on the common valid area (pixels usable on both dates, 2.2684 km²): candidate water is 0.1296 km² on 4 June and 0.1332 km² on 5 June. The difference shrinks from 0.1012 km² (full usable area) to 0.0036 km², about 9 pixels of 400 m², so almost all of the apparent difference was caused by the different masks. Water share of the common area is 5.71% vs 5.87%. The remaining difference could reflect mixed boundary pixels, illumination or atmosphere, or MNDWI values close to the 0.0 threshold; I did not test which. The comparison covers only the part of the AOI that was clear on both dates, so it says nothing about the river section hidden by cloud on 4 June.

What disabling cloud screening changed, and what this means scientifically:

With cloud screening disabled (mask_policy nodata_only, 4 June river), usable coverage rises from 47.6% to 100.0% and the observed area from 2.2708 km² to 4.7704 km². Candidate water rises from 0.1300 km² to 0.2336 km² (about 259 more 400 m² pixels). The extra pixels are exactly those that SCL flagged as cloud, shadow or similar, so the larger coverage does not mean more useful information: nodata_only excludes only SCL classes 0 and 1 (missing and defective pixels), and cloud pixels still receive an MNDWI value and are classified as water or not water. A high fraction of finite values therefore does not establish scientific usefulness. QC reflects this: the screened request was rejected for low usable coverage at a 0.5 minimum, while the unscreened one is only marked "review" because cloud screening was disabled. Its water area is close to that of the clear 5 June scene, but I did not verify that the extra water pixels are real water; I only compared totals.

Effect of changing the MNDWI threshold; request identity evidence:

Raising the MNDWI threshold from 0.0 to 0.15 on the clear 5 June river scene leaves the observed area unchanged (4.7416 km², 99.4% usable coverage) but reduces candidate water from 0.2312 km² to 0.1816 km². This is a loss of 0.0496 km² (124 pixels of 400 m², about 21%). The mask is identical, so the whole change comes from the classification rule: pixels with MNDWI between 0.0 and 0.15 are no longer counted as water. I did not check where these pixels are; I expect boundary or mixed pixels, but that is a hypothesis.

Request identity evidence (query on processing_requests): the new configuration produced a new request. For the 5 June river scene (same scene, bbox and mask policy), threshold 0.0 is request-8ce2a82b82fa and threshold 0.15 is request-43ad6f1beef1. The threshold is a scientific parameter included in the frozen specification and its hash, so changing it gives a different request_id and a new attempt. The earlier request and its outputs remain in the catalogue unchanged. The catalogue holds 8 requests in total.

Choosing a threshold: 0.0 and 0.15 are teaching comparisons, not validated water classifiers (docs/SOURCES.md). For a real purpose I would compare candidate water with an independent reference for the same date (for example a manually digitised river channel or an orthophoto), count omitted and added pixels for several thresholds, choose a value that balances them, and check its stability on another date.

QC policy change: assessment IDs before/after, and processing-attempt count:
Before: assessments 1-6 (minimum valid fraction 0.5): 2 rejected (both 4 June, usable coverage 47.6% and 48.5%) and 4 accepted. Assessment 7 is the nodata_only diagnostic (review). After: assessments 8-13 (minimum 0.995): all 6 rejected. I accidentally ran the same command twice, so assessments 14-19 repeat 8-13 with identical outcomes; the table is append-only and does not deduplicate. Processing attempts: 8 before and 8 after, so assess started none (processing_attempts_started was 0). Old attempts remain "succeeded": execution and scientific suitability are separate facts, and the measured usable fraction is stored with each attempt. The four clear scenes have 99.05-99.40% usable pixels, just below 99.5%. For river on 5 June, 11,854 of 11,926 pixels are usable and 11,867 would be needed, so 13 pixels decide the outcome.

One useful SQL query and what its actual output tells me:

Query: assessment history per attempt (scientific_qc_assessments, with minimum_valid_fraction from policy_json and valid_fraction from metrics_json). For attempt-6037e0c1... (river, 5 June) it shows accepted at 0.5 (assessment 3) and rejected at 0.995 (assessments 10 and 16) with the same observed valid fraction 0.99396. The conclusion changed only because the policy changed; the measurement and the execution status did not.

Request identity evidence (query on processing_requests): for the 5 June river scene, threshold 0.0 gives request-8ce2a82b82fa and threshold 0.15 gives request-43ad6f1beef1; scene, bbox and mask policy are identical, so the threshold alone produced a new request. Likewise, for the 4 June river scene, mask_policy scl (request-cfd9260532b4) and nodata_only (request-d8a75a1e8b21) are different requests. The catalogue holds 8 requests in total.

## My scientific product

Question and link to the science plan: How does vegetation moisture-related spectral response vary within the selected area of Las Wolski, Kraków, based on Sentinel-2 Level-2A imagery acquired on 5 June 2025?

The scientific product is the Normalized Difference Moisture Index (NDMI), calculated from Sentinel-2 surface reflectance data. The science plan focuses on assessing vegetation moisture-related conditions using multispectral Earth observation data.

Exact commands for acquisition/registration, planning, processing, assessment and report:

The workflow was executed from the Lab06 project directory using the Anaconda environment.

Processing command:

python -m eo_processing run --manifest work/personal/batch_v3.json

The final repeated execution returned complete: true and launched_attempts: [], confirming that the completed attempt was reused without unnecessary reprocessing.

Report generation:

python -m eo_processing report --manifest work/personal/batch_v3.json --out work/personal/report/report_v3_check.json

The independent pixel-level verification was performed using:

python check_ndmi_pixels.py


The acquisition and item registration were based on the existing project catalogue and the selected Sentinel-2 item.




Input bundle: manifest path, source item IDs, band list, checksums and where the retained subset files can be accessed:


Final manifest: work/personal/batch_v3.json

Configuration: config/personal_batch_v3.json

Source item ID: S2C_T34UDA_20250605T095638_L2A

Acquisition date: 2025-06-05

AOI: [19.84, 50.04, 19.87, 50.06]

Required bands: nir08 and swir16

Output CRS: EPSG:32634

Output resolution: 20 m

The retained processing outputs are available in:

work/personal/outputs/attempt-6f61505784044c0193297fd3a2d10608/

Files:

index.tif

valid_mask.tif

receipt.json

The SHA-256 checksums of the final output layers are recorded in receipt.json:

index.tif: 689678867605233cb473899193ecaace1b2b08c5645782c302ce680edd125c27

valid_mask.tif: 411bc03c0cb71ec7b1201be8867afe386ae9149bb9fd9fcd4d7e4a0527c701a0

The retained source subset files are managed through the project's catalogue and workspace.



Extension path/version, configuration paths and frozen manifests:


Custom extension: extensions/my_product.py

Product name: ndmi

Extension version: 1.0.1

Configuration: config/personal_batch_v3.json

Frozen execution manifest: work/personal/batch_v3.json

The extension uses the shared normalized_difference function from eo_processing.products.

Repeat/reuse evidence and changed-request evidence:

Three processing attempts were recorded during development:

Initial attempt: attempt-1c6cd889eb154dc3bd837b24a51617de

Second attempt: attempt-d69c13390bc44f09af4045cacbc35a9d

Final corrected attempt: attempt-6f61505784044c0193297fd3a2d10608

The final implementation corrected the NDMI denominator handling by using the shared normalized-difference implementation, where epsilon is used as a denominator validity threshold rather than being added to the denominator.

The final repeated execution returned launched_attempts: [] and complete: true, providing evidence of idempotent reuse.

Independent check, expected result, measured result and interpretation:

An independent pixel-level check recalculated NDMI from the NIR and SWIR input values and compared the results with the generated GeoTIFF.

Expected result: independently calculated NDMI values should match the corresponding raster pixels within floating-point precision.

Measured result:

Usable pixels: 11,751

Maximum absolute difference: 5.960464477539063e-08

Mean absolute difference: 1.1052243564790842e-08

The independent check passed. The very small differences are consistent with floating-point precision and confirm that the raster values agree with the NDMI equation.

The output range was also checked against the theoretical NDMI range of [-1, 1]. No values outside this range were detected.

Scientific finding, usable coverage and a suspected false detection or limitation:

The final NDMI raster contains 11,751 valid pixels, with a mean NDMI of approximately 0.3621, a minimum of -0.2083 and a maximum of 0.5577.

The usable pixel fraction is approximately 98.39% of the AOI pixels. The mean positive NDMI indicates a generally positive vegetation moisture-related spectral response in the valid part of the study area.

This result should not be interpreted as a direct measurement of soil or plant water content. NDMI is a spectral proxy and can be affected by vegetation structure, mixed pixels, shadows and other surface characteristics.

A further limitation is that no cloud-classified SCL pixels (classes 8, 9 or 10) occurred inside the selected AOI. Therefore, the cloud masking configuration was applied, but its effectiveness against actual cloud pixels was not independently demonstrated for this particular scene.


Core verification result:

The final processing attempt succeeded. The output raster was independently checked against the NDMI equation, with a maximum absolute pixel difference of approximately 5.96 × 10⁻⁸.

The raster has the expected CRS (EPSG:32634), 20 m resolution and nominal NDMI range. The report was generated successfully and the final execution was reusable without launching another attempt.

Overall, the core numerical and workflow verification passed.


Assistance used and how I verified it:

AI assistance (ChatGPT) was used to support implementation, debugging, configuration and interpretation of the processing workflow.

The generated implementation was not accepted solely on the basis of AI suggestions. It was verified by:

inspecting the custom plugin source code;

checking the processing configuration and manifest;

examining the execution receipt and logs;

independently recalculating NDMI values for selected pixels;

comparing the independent calculations with the generated GeoTIFF;

checking raster dimensions, CRS, resolution, valid pixel count and value range;

generating and opening the final processing report.



## Optional debugging clinic

Why the file existed even though the real attempt failed:

My file mode correction, and why it preserves existing bytes:

Verification result, and why the main core still matches the release:

Why the original runner correction needed new manifests while this exercise does not:
