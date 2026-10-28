import os
import subprocess
import html

def md_to_html(md_path, html_path):
    with open(md_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    html_out = []
    html_out.append('''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>DigiQ Audit Report</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; line-height: 1.6; color: #1e293b; max-width: 900px; margin: 0 auto; padding: 30px; font-size: 13px; }
  h1 { font-size: 22px; border-bottom: 2px solid #0284c7; padding-bottom: 8px; color: #0369a1; }
  h2 { font-size: 18px; border-bottom: 1px solid #cbd5e1; padding-bottom: 6px; margin-top: 24px; color: #0f172a; }
  h3 { font-size: 15px; margin-top: 18px; color: #334155; }
  h4 { font-size: 13px; margin-top: 14px; }
  table { border-collapse: collapse; width: 100%; margin: 15px 0; font-size: 12px; }
  th, td { border: 1px solid #cbd5e1; padding: 6px 10px; text-align: left; }
  th { background-color: #f1f5f9; font-weight: 600; }
  tr:nth-child(even) { background-color: #f8fafc; }
  pre { background: #0f172a; color: #f8fafc; padding: 12px; border-radius: 6px; overflow-x: auto; font-size: 11px; font-family: Consolas, monospace; }
  code { background: #e2e8f0; padding: 2px 4px; border-radius: 4px; font-size: 11px; font-family: Consolas, monospace; }
  pre code { background: none; padding: 0; color: inherit; }
  blockquote { border-left: 4px solid #0284c7; margin: 10px 0; padding: 5px 15px; background: #f0f9ff; color: #0369a1; }
  hr { border: none; border-top: 1px solid #e2e8f0; margin: 20px 0; }
  .badge-pass { background: #dcfce7; color: #15803d; padding: 2px 6px; border-radius: 4px; font-weight: bold; }
  .badge-fail { background: #fee2e2; color: #b91c1c; padding: 2px 6px; border-radius: 4px; font-weight: bold; }
  @media print {
    body { padding: 10px; }
    pre { white-space: pre-wrap; word-wrap: break-word; }
  }
</style>
</head>
<body>
''')

    in_code = False
    in_table = False
    table_lines = []

    for line in lines:
        stripped = line.strip()
        if stripped.startswith('```'):
            if in_code:
                html_out.append('</code></pre>\n')
                in_code = False
            else:
                lang = stripped[3:].strip()
                html_out.append(f'<pre><code class="language-{lang}">')
                in_code = True
            continue

        if in_code:
            html_out.append(html.escape(line))
            continue

        if stripped.startswith('|') and stripped.endswith('|'):
            if not in_table:
                in_table = True
                html_out.append('<table>\n')
            
            cells = [c.strip() for c in stripped.strip('|').split('|')]
            if all(set(c).issubset({'-', ':', ' '}) for c in cells):
                continue
            
            is_header = ('<th>' not in "".join(html_out[-3:])) if in_table else False
            row_tag = 'th' if '<thead>' not in "".join(html_out[-10:]) and len(html_out) > 0 and html_out[-1] == '<table>\n' else 'td'
            
            row_html = '  <tr>' + ''.join(f'<{row_tag}>{html.escape(c)}</{row_tag}>' for c in cells) + '</tr>\n'
            html_out.append(row_html)
            continue
        else:
            if in_table:
                html_out.append('</table>\n')
                in_table = False

        if stripped.startswith('# '):
            html_out.append(f'<h1>{html.escape(stripped[2:])}</h1>\n')
        elif stripped.startswith('## '):
            html_out.append(f'<h2>{html.escape(stripped[3:])}</h2>\n')
        elif stripped.startswith('### '):
            html_out.append(f'<h3>{html.escape(stripped[4:])}</h3>\n')
        elif stripped.startswith('#### '):
            html_out.append(f'<h4>{html.escape(stripped[5:])}</h4>\n')
        elif stripped.startswith('---'):
            html_out.append('<hr>\n')
        elif stripped.startswith('> '):
            html_out.append(f'<blockquote>{html.escape(stripped[2:])}</blockquote>\n')
        elif stripped.startswith('- ') or stripped.startswith('* '):
            html_out.append(f'<li>{html.escape(stripped[2:])}</li>\n')
        elif stripped:
            html_out.append(f'<p>{html.escape(stripped)}</p>\n')

    if in_table:
        html_out.append('</table>\n')
    if in_code:
        html_out.append('</code></pre>\n')

    html_out.append('</body></html>')

    with open(html_path, 'w', encoding='utf-8') as f:
        f.write("".join(html_out))
    print(f"Generated {html_path}")

def export_pdf():
    md_to_html('audit/REPORT.md', 'audit/REPORT.html')
    edge_path = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    cwd = os.getcwd()
    html_abs = os.path.join(cwd, 'audit', 'REPORT.html')
    pdf_abs = os.path.join(cwd, 'audit', 'REPORT.pdf')
    
    cmd = [
        edge_path,
        '--headless',
        '--disable-gpu',
        '--run-all-compositor-stages-before-draw',
        f'--print-to-pdf={pdf_abs}',
        f'file:///{html_abs.replace(os.sep, "/")}'
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if os.path.exists(pdf_abs):
        print(f"Exported PDF successfully to {pdf_abs} (size: {os.path.getsize(pdf_abs)} bytes)")
    else:
        print(f"PDF export failed: {res.stderr}")

if __name__ == '__main__':
    export_pdf()

