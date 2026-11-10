"""Regenerate the whole household-hard fixture: vault/, drops/*.txt, filing.json, questions.json.

    python3 eval/household-hard/tools/gen/build_all.py

Order matters: CSVs first (notes and GENERATED reports read them), questions last
(they import tools/answers.py, which reads the CSVs). Files are overwritten in place;
nothing is deleted, so remove vault/ first if you renamed a note.
"""
import csvs, finance, home, health, life, private, career_root, drops

csvs.main(); finance.main(); home.main(); health.main(); life.main()
private.main(); career_root.main(); drops.main()
import runpy, os
runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "questions.py"), run_name="__main__")
