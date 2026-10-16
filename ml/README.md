# ml/ — what you must do, and what is already wired

**Status: no model, no dataset, no training has been done.** Nothing here claims an accuracy.

## Your manual steps (in order)

1. **Decide classes** in `datasets/dataset_schema.yaml` (default: fresh / rotten / sprouted / skin_peel). Every defect class needs a `detail_key`; the backend's grading rules reference `rot_pct`, `sprout_pct` by these keys.
2. **Collect + label** photos in YOLO detection format under `ml/datasets/onions/{train,val,test}/{images,labels}`. Split by photo session, not by crop.
3. **Validate:** `python ml/scripts/validate_dataset.py --root ml/datasets/onions --classes 4`. Fix every PROBLEM.
4. **Train** by completing `training/train_template.py` (or your own notebook).
5. **Evaluate** on `test/` only once: predict into YOLO txt files with a 6th confidence column, then `python ml/evaluation/evaluate.py --gt .../test/labels --pred <preds> --classes 4 --metadata ml/artifacts/model_metadata.json`. Copy the numbers you measured into `metadata.metrics`.
6. **Export** INT8 or float TFLite to `ml/artifacts/onion_model.tflite`; write `ml/artifacts/model_metadata.json` from `contract/model_metadata.EXAMPLE.json` (see schema). Record the real output tensor indices.
7. **Validate artifacts:** `pip install ai-edge-litert jsonschema && python ml/scripts/validate_artifacts.py`. It must print `OK` and the "tensors match" note.
8. **Install:** copy both files to `app/assets/model/`, rebuild the app. The backend reads `ml/artifacts/` directly (set `MODEL_METADATA_PATH`/`MODEL_FILE_PATH` if elsewhere) and will only accept certificates whose `model_version` equals `metadata.version`.
9. **Admin publishes grading rules** (`POST /api/v1/rules`). Thresholds are policy (NAFED), not model output; I did not invent them.
10. **Do a real-device test** on photos not in train/val. Measure latency yourself before repeating any "<1 s on ₹6,000 phone" claim.

## Contract summary
`contract/model_metadata.schema.json` is enforced by the backend, `validate_artifacts.py`, and the app loader. `inference/postprocess.py` defines how detections become `onion_count / fresh_pct / defective_pct / details / batch_confidence`; `contract/postprocess_vectors.json` lets Python and Dart tests check they agree.

## Honest caveats about the PPT's ML claims
- **ViT-YOLO on a ₹6,000 phone, INT8, <1 s, 50+ onions:** unproven. Transformer backbones quantise worse than CNNs. Budget time to benchmark a plain YOLO-nano baseline; if it meets accuracy it is the safer choice. The contract is architecture-agnostic.
- **Grad-CAM "heatmap":** Grad-CAM explains a classifier, and detectors don't expose it directly. The app draws **detection boxes** as visual proof. It shows a heatmap only if you add one and declare `outputs.heatmap` (rendering code for that is not written).
- **Rot "area %":** needs segmentation. The shipped metrics are count-based per onion.
- **Diameter (mm), MiDaS weight check, shelf-life GBR, histogram equalisation tuning:** need your data/calibration. Backend fields exist (`estimated_weight_kg`, `details.shelf_life_days`, `details.median_diameter_mm`); the app does not compute them.
