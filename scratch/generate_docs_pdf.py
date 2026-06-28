import os
import subprocess
import sys

# Ensure ReportLab is installed
try:
    import reportlab
except ImportError:
    print("Installing reportlab...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "reportlab"])

from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfgen import canvas

class NumberedCanvas(canvas.Canvas):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_number(num_pages)
            super().showPage()
        super().save()

    def draw_page_number(self, page_count):
        if self._pageNumber == 1:
            return  # skip title page
        self.saveState()
        self.setFont("Helvetica", 9)
        self.setFillColor(colors.HexColor("#4b5563"))
        
        # Header
        self.drawString(54, 750, "Supabase Transformation Layer - Logic & Architecture Documentation")
        self.setStrokeColor(colors.HexColor("#e5e7eb"))
        self.setLineWidth(0.5)
        self.line(54, 742, 558, 742)
        
        # Footer
        page_text = f"Page {self._pageNumber} of {page_count}"
        self.drawRightString(558, 40, page_text)
        self.drawString(54, 40, "CONFIDENTIAL - CJMN Technologies")
        self.line(54, 52, 558, 52)
        self.restoreState()

def build_pdf(filename="Transformation Layer/Transformation_Layer_Documentation.pdf"):
    # Ensure parent directory exists
    parent_dir = os.path.dirname(filename)
    if parent_dir and not os.path.exists(parent_dir):
        os.makedirs(parent_dir)

    doc = SimpleDocTemplate(
        filename,
        pagesize=letter,
        rightMargin=54,
        leftMargin=54,
        topMargin=72,
        bottomMargin=72
    )

    styles = getSampleStyleSheet()

    # Custom styles
    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=24,
        leading=30,
        textColor=colors.HexColor('#1e3a8a'),
        spaceAfter=15,
        alignment=1
    )

    subtitle_style = ParagraphStyle(
        'DocSubtitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=12,
        leading=16,
        textColor=colors.HexColor('#4b5563'),
        spaceAfter=40,
        alignment=1
    )

    meta_style = ParagraphStyle(
        'DocMeta',
        parent=styles['Normal'],
        fontName='Helvetica-Oblique',
        fontSize=9,
        leading=13,
        textColor=colors.HexColor('#9ca3af'),
        spaceAfter=15,
        alignment=1
    )

    h1_style = ParagraphStyle(
        'Heading1_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=16,
        leading=20,
        textColor=colors.HexColor('#1e3a8a'),
        spaceBefore=18,
        spaceAfter=8,
        keepWithNext=True
    )

    h2_style = ParagraphStyle(
        'Heading2_Custom',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=11,
        leading=15,
        textColor=colors.HexColor('#0f766e'),
        spaceBefore=10,
        spaceAfter=4,
        keepWithNext=True
    )

    body_style = ParagraphStyle(
        'Body_Custom',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9,
        leading=13.5,
        textColor=colors.HexColor('#1f2937'),
        spaceAfter=6
    )

    code_style = ParagraphStyle(
        'Code_Custom',
        parent=styles['Normal'],
        fontName='Courier',
        fontSize=7.5,
        leading=10,
        textColor=colors.HexColor('#111827'),
        spaceAfter=6,
        leftIndent=15
    )

    list_style = ParagraphStyle(
        'List_Custom',
        parent=body_style,
        leftIndent=15,
        spaceAfter=3
    )

    story = []

    # ================= TITLE PAGE =================
    story.append(Spacer(1, 100))
    story.append(Paragraph("SUPABASE TRANSFORMATION LAYER", title_style))
    story.append(Paragraph("Unified Technical Specification & Architecture Design Documentation", subtitle_style))
    story.append(Spacer(1, 150))
    
    meta_text = """
    <b>Prepared for:</b> CJMN Technologies<br/>
    <b>Author:</b> Antigravity AI Assistant (DeepMind Coding Team)<br/>
    <b>Date:</b> June 28, 2026<br/>
    <b>Version:</b> 2.0.0 (Classified Subdirectory Release)<br/>
    <b>Status:</b> Fully Automated & Verified
    """
    story.append(Paragraph(meta_text, meta_style))
    story.append(PageBreak())

    # ================= SECTION 1 =================
    story.append(Paragraph("1. Executive Summary & Architectural Overview", h1_style))
    story.append(Paragraph(
        "The Supabase Transformation Layer coordinates the integration, standardization, and hour-level expansion "
        "of transportation metrics, weather observations, and academic/governmental transit-affecting announcements. "
        "The objective of this layer is to construct a standardized, real-time dataset ready for calculating the "
        "Commuter Friction Index (CFI).",
        body_style
    ))
    story.append(Paragraph(
        "The system has been engineered to process raw incoming scraped inputs (such as PAGASA weather feeds and LGU "
        "Facebook posts) and convert them automatically into standardized formats in real time. It is driven by "
        "PostgreSQL triggers, eliminating the need for periodic batch jobs or polling servers for active datasets.",
        body_style
    ))
    
    # ================= SECTION 2 =================
    story.append(Paragraph("2. File Structure & Dataset Classifications", h1_style))
    story.append(Paragraph(
        "In accordance with your dataset classification scheme, the SQL migration scripts have been organized "
        "into distinct subdirectories under the 'Transformation Layer' parent folder. This structures code "
        "based on data origins and references:",
        body_style
    ))

    # Classification Table
    data = [
        ["Classification", "Subdirectory", "File Name", "Role & Description"],
        ["Internal", "internal/", "restore_ridership_backups.sql", "Aggregates active hourly tables to raw backups."],
        ["Internal", "internal/", "standardize_internal_dimensions.sql", "Standardizes PSOR and Station Capacity PKs."],
        ["Internal", "internal/", "transform_ridership_hourly.sql", "Proportionally expands 5-year raw bands to hourly."],
        ["Internal", "internal/", "expand_student_transactions.sql", "Maps student transactions to 2025 hourly baseline."],
        ["External", "external/", "consolidate_weather_schema.sql", "Creates consolidated weather table and current/forecast syncs."],
        ["External", "external/", "consolidate_events_schema.sql", "Creates consolidated events table and calendar processor."],
        ["External", "external/", "standardize_external_triggers.sql", "Compiles classifiers, weather formulas, and A_sw triggers."],
        ["Literature", "literature/", "standardize_literature_dimensions.sql", "Sets up APTA tables and seeds literature friction weights."]
    ]

    t = Table(data, colWidths=[65, 60, 160, 215])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#1e3a8a')),
        ('TEXTCOLOR', (0,0), (-1,0), colors.whitesmoke),
        ('ALIGN', (0,0), (-1,-1), 'LEFT'),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTSIZE', (0,0), (-1,0), 8),
        ('BOTTOMPADDING', (0,0), (-1,0), 4),
        ('TOPPADDING', (0,0), (-1,0), 4),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,1), (-1,-1), 7.5),
        ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor('#e5e7eb')),
        ('BACKGROUND', (0,1), (-1,-1), colors.HexColor('#f9fafb')),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
        ('BOTTOMPADDING', (0,1), (-1,-1), 4),
        ('TOPPADDING', (0,1), (-1,-1), 4),
    ]))
    story.append(t)
    story.append(Spacer(1, 10))
    story.append(PageBreak())

    # ================= SECTION 3 =================
    story.append(Paragraph("3. Core Ingestion & Normalization Logic", h1_style))
    
    # 3.1 Weather
    story.append(Paragraph("3.1. Meteorological Friction Scoring (PAGASA)", h2_style))
    story.append(Paragraph(
        "Weather friction is computed using raw observations and forecast fields from PAGASA API feeds, "
        "governed by trigger-based executions on the weather tables. The pipeline applies a standardized "
        "normalization scale matching index variables:",
        body_style
    ))
    story.append(Paragraph("• <b>Clear / Fair</b>: Wind signal = 0, Rainfall < 5mm, level = 'None' → <b>score = 0.0</b>", list_style))
    story.append(Paragraph("• <b>Moderate Friction</b>: Wind signal = 1, Rainfall 5-40mm, or level = 'Yellow' → <b>score = 0.4</b>", list_style))
    story.append(Paragraph("• <b>Severe Friction</b>: Wind signal >= 2 or Rainfall > 40mm or level = 'Orange'/'Red' → <b>score = 0.8</b>", list_style))
    story.append(Paragraph("• <b>Extreme Friction</b>: Both severe wind (Signal >= 2) and severe rainfall (> 40mm) occur → <b>score = 1.0</b>", list_style))
    story.append(Paragraph(
        "The trigger `tg_sync_weather_current` and `tg_sync_weather_forecasts` calculate these scores dynamically "
        "and record them in `weather_consolidated.normalized_score`, alongside a reference to the raw literature weight "
        "(`friction_weight_ref`) and the trigger categories (`event_category` = 'weather_advisory', `trigger_category` = PAGASA descriptor).",
        body_style
    ))

    # 3.2 Events Classifier
    story.append(Paragraph("3.2. Regex-Based Qualitative Classifier & Priority Resolution", h2_style))
    story.append(Paragraph(
        "For scraped Facebook postings and LGU announcements, the classifier function `classify_event_from_text` parses "
        "post texts and image texts. It resolves priorities chronologically using structured regex matches:",
        body_style
    ))
    story.append(Paragraph(
        "1. <b>Administrative/Planning Exclusions (False Positive Filter)</b>:<br/>"
        "Intercepts text containing 'coordination meeting', 'ocular visit', or 'planning session' and maps it to "
        "`event_category := 'administrative'` (which sets `affects_ridership := FALSE`), preventing these notices "
        "from affecting transit. If the notice explicitly declares a suspension/strike (e.g. 'no classes', 'tigil pasada'), "
        "the meeting filter is bypassed.",
        list_style
    ))
    story.append(Paragraph(
        "2. <b>Administrative/Grades Release Exclusions</b>:<br/>"
        "Intercepts internal notices like grade posting, releases, subject dropping, or deliberations, mapping them to "
        "non-relevant administrative categories to prevent false matches with exam keywords.",
        list_style
    ))
    story.append(Paragraph(
        "3. <b>School Breaks & Vacations</b>: Identifies scheduled breaks, categorized as `school_break` (trigger_category = 'School Break').",
        list_style
    ))
    story.append(Paragraph(
        "4. <b>Class Suspensions & Holidays</b>: Identifies holidays and suspension notices, categorized as `class_suspension` (trigger_category = 'Class Suspension / Holiday').",
        list_style
    ))
    story.append(Paragraph(
        "5. <b>Transport Strikes</b>: Identifies public transport strikes (jeepney strikes, PISTON, Manibela), categorized as `transport_strike`.",
        list_style
    ))
    story.append(Paragraph(
        "6. <b>Major Events</b>: Identifies UAAP/NCAA games, arena concerts, pep rallies, and sports days, categorized as `major_event`.",
        list_style
    ))
    story.append(Paragraph(
        "7. <b>Exam Weeks</b>: Identifies midterm/final exam periods, categorized as `exam_week`.",
        list_style
    ))
    story.append(Paragraph(
        "8. <b>Academic Start/Enrollment</b>: Identifies orientation and enrollment weeks, categorized as `regular_class_day`.",
        list_style
    ))

    # 3.3 ASW Trigger
    story.append(Paragraph("3.3. Academic Surge Weight (A_sw) Dynamic Density Trigger", h2_style))
    story.append(Paragraph(
        "Academic events categorized as `major_event` are normalized dynamically based on active event density "
        "occurring at a specific station on a given date:",
        body_style
    ))
    story.append(Paragraph("• <b>0 major events</b> on date/station → <b>A_sw = 0.0</b>", list_style))
    story.append(Paragraph("• <b>1 or 2 major events</b> on date/station → <b>A_sw = 0.5</b>", list_style))
    story.append(Paragraph("• <b>3 or more major events</b> on date/station → <b>A_sw = 1.0</b>", list_style))
    story.append(Paragraph(
        "The trigger `tg_recalculate_asw` binds to `external.events_consolidated`. On inserts, updates, or deletes, "
        "it dynamically counts all major events on the target date/station and updates all corresponding rows. "
        "To prevent infinite recursion in PostgreSQL, the update executes only when the calculated score is "
        "<b>DISTINCT FROM</b> the row's existing score.",
        body_style
    ))
    story.append(PageBreak())

    # 3.4 Ridership hourly
    story.append(Paragraph("3.4. 5-Year Ridership Proportional Hourly Expansion", h2_style))
    story.append(Paragraph(
        "Raw ridership is aggregated in historical files into broad shift bands (e.g. 5-7am, 7-9am, 9am-5pm, 5-7pm, 7-10pm). "
        "The database function `transform_ridership_table(p_year)` dynamically discover entry/exit station columns and "
        "expands these bands into hour-level rows by applying weights derived from empirical transit flows:",
        body_style
    ))
    
    # Weight Table
    weight_data = [
        ["Shift Band", "Hour Period", "Empirical Weight (%)", "Cumulative Weight"],
        ["5-7am (OFF PEAK)", "05:00", "29.49%", "0.29497"],
        ["", "06:00", "70.50%", "1.00000"],
        ["7-9am (AM PEAK)", "07:00", "54.40%", "0.54402"],
        ["", "08:00", "45.59%", "1.00000"],
        ["9am-5pm (OFF PEAK)", "09:00", "11.58%", "0.11581"],
        ["", "10:00", "10.95%", "0.22536"],
        ["", "11:00", "11.25%", "0.33788"],
        ["", "12:00", "12.52%", "0.46318"],
        ["", "13:00", "12.27%", "0.58592"],
        ["", "14:00", "12.25%", "0.70843"],
        ["", "15:00", "13.38%", "0.84227"],
        ["", "16:00", "15.77%", "1.00000"],
        ["5-7pm (PM PEAK)", "17:00", "51.49%", "0.51492"],
        ["", "18:00", "48.50%", "1.00000"],
        ["7-10pm (OFF PEAK)", "19:00", "51.20%", "0.51200"],
        ["", "20:00", "36.79%", "0.87999"],
        ["", "21:00", "12.00%", "1.00000"]
    ]
    
    wt = Table(weight_data, colWidths=[120, 100, 140, 140])
    wt.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#0f766e')),
        ('TEXTCOLOR', (0,0), (-1,0), colors.whitesmoke),
        ('ALIGN', (0,0), (-1,-1), 'LEFT'),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTSIZE', (0,0), (-1,0), 8),
        ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor('#e5e7eb')),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,1), (-1,-1), 7.5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 2),
        ('TOPPADDING', (0,0), (-1,-1), 2),
        ('BACKGROUND', (0,1), (-1,-1), colors.HexColor('#f9fafb')),
    ]))
    story.append(wt)
    story.append(Spacer(1, 10))
    story.append(Paragraph(
        "<b>Cumulative Rounding & Nulls:</b> To maintain integer precision, the script uses a double-layered cumulative rounding "
        "strategy (multiplying the total row count by the cumulative weight sum, rounding, and subtracting the previous "
        "rounded sum). The script wraps all columns in `COALESCE(col, 0)` to handle historical missing/NULL cells and "
        "preserve the mathematical total.",
        body_style
    ))

    # 3.5 Student transactions
    story.append(Paragraph("3.5. Student Transactions Expansion & Weekday Mapping", h2_style))
    story.append(Paragraph(
        "Student transaction records are available only as monthly summaries. The pipeline expands them proportionally "
        "into daily/hourly rows using the 2025 commuter ridership as the proportional template profile:",
        body_style
    ))
    story.append(Paragraph(
        "• <b>2026 Weekday Mapping</b>: Since student schedules are highly dependent on school days, 2026 dates are mapped "
        "to a matching 2025 baseline date based on month, day of week, and proximity (e.g. Friday, Jan 2, 2026 maps to Friday, Jan 3, 2025). "
        "This preserves weekend/weekday profiles and academic seasonality.",
        list_style
    ))
    story.append(Paragraph(
        "• <b>Allocation Denominator Safeguard</b>: In raw datasets, there are discrepancies where the sum of station columns "
        "differs from the pre-computed `total_entry`/`total_exit` columns. Using the total column as a denominator can lead "
        "to negative numbers (e.g. `-1` entries) on final stations due to rounding overflows. The script calculates the "
        "<b>actual sum of the station columns</b> dynamically and uses that sum as the denominator, mathematically guaranteeing "
        "non-negative integer allocations for all 13 stations.",
        list_style
    ))
    story.append(Paragraph(
        "• <b>Date Constraints</b>: The dataset is restricted strictly to the non-zero student transaction period: "
        "<b>June 2025 to March 2026</b>.",
        list_style
    ))
    story.append(PageBreak())

    # ================= SECTION 4 =================
    story.append(Paragraph("4. Automated Integrity Verification Suite", h1_style))
    story.append(Paragraph(
        "To ensure continuous data validation and prevent pipeline errors, the orchestrator script `run_pipeline.js` "
        "incorporates a comprehensive suite of verification tests that run automatically after database migrations:",
        body_style
    ))
    
    story.append(Paragraph(
        "1. <b>Row Sum Discrepancy Check</b>:<br/>"
        "Verifies that the sum of the 13 station entry/exit columns matches the `total_entry` and `total_exit` columns exactly. "
        "(Historical source discrepancies on June 2023 and Nov 1, 2023, are safely bypassed).",
        list_style
    ))
    story.append(Paragraph(
        "2. <b>Negative Value Check</b>:<br/>"
        "Verifies that there are zero negative values in all columns across the 5 years and the student transaction table.",
        list_style
    ))
    story.append(Paragraph(
        "3. <b>Primary Key Uniqueness Check</b>:<br/>"
        "Asserts that row counts match distinct primary key counts, ensuring zero duplicate IDs.",
        list_style
    ))
    story.append(Paragraph(
        "4. <b>Monthly Student Transaction Conservation</b>:<br/>"
        "Verifies that the sum of the expanded hourly student rows for each month matches the original monthly total "
        "with 100% precision.",
        list_style
    ))
    story.append(Paragraph(
        "5. <b>Meeting Classifier False Positive Check</b>:<br/>"
        "Asserts that 0 coordination meetings or preparation events are classified as active transit anomalies.",
        list_style
    ))
    story.append(Paragraph(
        "6. <b>Holiday/Break Normalization Check</b>:<br/>"
        "Asserts that 100% of class suspensions and school break holidays have `normalized_score = 1.0`.",
        list_style
    ))
    story.append(Paragraph(
        "7. <b>Academic Surge Weight (A_sw) Density Check</b>:<br/>"
        "Validates that all major events are correctly grouped and updated to their aggregate density scores (0.5 for 1-2 events, 1.0 for >=3 events).",
        list_style
    ))

    # ================= SECTION 5 =================
    story.append(Spacer(1, 10))
    story.append(Paragraph("5. Execution Flow & Automation State", h1_style))
    story.append(Paragraph(
        "The Supabase Transformation Layer is now in a <b>fully automated, trigger-driven state</b>. "
        "The execution orchestration follows the path defined in `run_pipeline.js`:",
        body_style
    ))

    # Table of files
    pipeline_data = [
        ["Order", "SQL Target File", "Scope", "Role in Pipeline"],
        ["1", "internal/restore_ridership_backups.sql", "Internal", "Reaggregates hourly rows to raw backup tables."],
        ["2", "internal/standardize_internal_dimensions.sql", "Internal", "Resets PSOR and Station Capacity dimensions."],
        ["3", "literature/standardize_literature_dimensions.sql", "Literature", "Resets APTA and seeds friction weights references."],
        ["4", "external/standardize_external_triggers.sql", "External", "Deploys classifiers, weather formulas, and triggers."],
        ["5", "internal/transform_ridership_hourly.sql", "Internal", "Converts backups to hourly active ridership tables."],
        ["6", "internal/expand_student_transactions.sql", "Internal", "Expands student transaction summaries to hourly data."]
    ]
    
    ptable = Table(pipeline_data, colWidths=[40, 180, 70, 210])
    ptable.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#1e3a8a')),
        ('TEXTCOLOR', (0,0), (-1,0), colors.whitesmoke),
        ('ALIGN', (0,0), (-1,-1), 'LEFT'),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('FONTSIZE', (0,0), (-1,0), 8),
        ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor('#e5e7eb')),
        ('FONTNAME', (0,1), (-1,-1), 'Helvetica'),
        ('FONTSIZE', (0,1), (-1,-1), 7.5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3),
        ('TOPPADDING', (0,0), (-1,-1), 3),
        ('BACKGROUND', (0,1), (-1,-1), colors.HexColor('#f9fafb')),
    ]))
    story.append(ptable)
    story.append(Spacer(1, 10))
    story.append(Paragraph(
        "Once this pipeline has been run once to setup the schema, triggers, and historical datasets, "
        "<b>no further manual execution is required</b>. Any new scraped data inserted into raw tables "
        "will instantly calculate friction indexes and populate the analytics tables automatically in real time.",
        body_style
    ))

    # Build the document
    doc.build(story, canvasmaker=NumberedCanvas)
    print("PDF Generation complete.")

if __name__ == "__main__":
    build_pdf()
