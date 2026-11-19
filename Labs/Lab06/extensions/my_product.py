
"""Normalized Difference Moisture Index (NDMI).

NDMI = (NIR - SWIR1) / (NIR + SWIR1)

Reference:
USGS - Normalized Difference Moisture Index
https://www.usgs.gov/landsat-missions/normalized-difference-moisture-index
"""

import numpy as np
from eo_processing.products import (
    ProductResult,
    normalized_difference
)


class NDMI:
    name = "ndmi"
    version = "1.0.1"

    required_bands = ("nir08", "swir16")
    output_roles = ("index",)
    primary_role = "index"
    nominal_range = (-1.0, 1.0)

    default_parameters = {
        "epsilon": 0.000001
    }

    def calculate(self, bands, valid, parameters, pixel_area_m2):

        nir = bands["nir08"]
        swir = bands["swir16"]

        index = normalized_difference(
            nir,
            swir,
            parameters["epsilon"]
        )

        index[~valid] = np.nan

        metric = (
            float(np.nanmean(index))
            if np.isfinite(index).any()
            else None
        )

        return ProductResult(
            {"index": index},
            {"mean_ndmi": metric}
        )


PRODUCT = NDMI()
