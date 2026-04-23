# Scripts

## `compare_with_azure.py`

Cross-validates the custom pronunciation engine against Azure Pronunciation
Assessment on your test fixtures. Produces `pronunciation_engine/validation_report.md`
for inclusion in the FYP dissertation's validation section.

### One-time setup

1. **Create a free Azure Speech resource** (~5 min):
   - Go to https://portal.azure.com
   - "Create a resource" → search for "Speech" → "Speech service"
   - Choose free tier **F0** (5 hours of audio per month — plenty for testing)
   - Pick any region close to you (e.g. `eastus`, `uksouth`, `westeurope`)
   - Create + wait ~1 min

2. **Grab your key and region**:
   - Open the resource → "Keys and Endpoint"
   - Copy KEY 1 and the region name

3. **Export before running**:
   ```bash
   export AZURE_SPEECH_KEY="paste_your_key_here"
   export AZURE_SPEECH_REGION="eastus"   # whichever region you picked
   ```

### Running

```bash
cd pronunciation_engine
# engine must be running locally — start it if not already:
docker compose up -d

python3 scripts/compare_with_azure.py
```

Output goes to `pronunciation_engine/validation_report.md`. Takes about 1 minute
for all 8 fixtures.

### What the report contains

- Per-fixture side-by-side scores (ours vs. Azure Accuracy / Fluency / Completeness / PronScore)
- Pearson correlation coefficient between our overall_score and Azure AccuracyScore
- Mean + max absolute difference
- Interpretation notes ready to paste into your dissertation's validation section
