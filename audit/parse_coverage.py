import os

def parse_lcov(path):
    if not os.path.exists(path):
        return "Coverage file not found."
    
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    file_cov = {}
    cur_file = None
    
    for l in lines:
        l = l.strip()
        if l.startswith('SF:'):
            cur_file = l[3:]
            file_cov[cur_file] = {'found': 0, 'hit': 0}
        elif l.startswith('DA:') and cur_file:
            parts = l[3:].split(',')
            file_cov[cur_file]['found'] += 1
            if len(parts) > 1 and int(parts[1]) > 0:
                file_cov[cur_file]['hit'] += 1
                
    total_found = sum(d['found'] for d in file_cov.values())
    total_hit = sum(d['hit'] for d in file_cov.values())
    pct = (total_hit / total_found * 100) if total_found else 0
    
    report = []
    report.append("==================================================")
    report.append("           DIGIQ CODE COVERAGE REPORT             ")
    report.append("==================================================")
    report.append(f"Total Source Lines Evaluated : {total_found}")
    report.append(f"Total Lines Covered (Hit)    : {total_hit}")
    report.append(f"Unit Test Line Coverage      : {pct:.2f}%\n")
    report.append("Files Analyzed:")
    for f, d in sorted(file_cov.items()):
        f_pct = (d['hit'] / d['found'] * 100) if d['found'] else 0
        report.append(f"  • {f:<50} : {d['hit']:>3}/{d['found']:<3} ({f_pct:5.1f}%)")
    report.append("==================================================")
    
    return "\n".join(report)

if __name__ == '__main__':
    res = parse_lcov('coverage/lcov.info')
    print(res)
    with open('audit/coverage-summary.txt', 'w', encoding='utf-8') as f:
        f.write(res)

