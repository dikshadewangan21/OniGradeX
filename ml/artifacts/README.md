# ml/artifacts/

Put exactly two files here:

| File | Source |
|------|--------|
| `onion_model.tflite` | your exported detector |
| `model_metadata.json` | filled-in copy of `ml/contract/model_metadata.EXAMPLE.json` |

Currently **empty on purpose**: no model has been trained. Backend `/api/v1/model/status` and the app's
model screen report "unavailable" until both files validate.

Then run `python ml/scripts/validate_artifacts.py`, and copy the same two files to `app/assets/model/`.
