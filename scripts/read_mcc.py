"""Export the complete source table, including missing actuals and date indicators."""
import sys
from pbixray import PBIXRay

records = PBIXRay(sys.argv[1]).get_table("itt_dataset_itt")
if len(records) != 4737 or not records.IndicatorId.is_unique:
    raise ValueError("MCC indicator grain differs from the validated release")
records.to_csv(sys.argv[2], index=False)
