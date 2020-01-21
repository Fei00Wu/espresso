import os
import sys

cmu_spk_tbl = sys.argv[1]
out_file = sys.argv[2]

age_lines = []
with open(cmu_spk_tbl, 'r') as fp:
    line = fp.readline()
    while line:
        toks = line.strip().split()

        if toks[0] != "#":
            spkID = toks[0] 
            grade_age = toks[2]
            grade, age = grade_age.split('/')
            age_lines.append(spkID + " " + age  + " " + grade + "\n")
        line = fp.readline()
fp.close()

fp = open(out_file, 'w+')
fp.writelines(age_lines)
