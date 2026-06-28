# G11-Transformation Project Agent Rules

Whenever you modify any SQL scripts, schemas, triggers, or execution sequences in the Transformation Layer:

1. **Keep Documentation Up to Date**:
   - Update `README.md` to reflect the latest database schemas, file classifications, or runner instructions.
   - Update and re-run the PDF documentation generator script `scratch/generate_docs_pdf.py` to keep the local PDF file current.

2. **PDF Location & Git Ignoring**:
   - The compiled PDF must ALWAYS be saved locally at:
     `Transformation Layer/Transformation_Layer_Documentation.pdf`
   - Under NO circumstances should the PDF file itself be pushed to GitHub (it is excluded via `.gitignore`).
   - The generator script `scratch/generate_docs_pdf.py` MUST be tracked and pushed to GitHub.
