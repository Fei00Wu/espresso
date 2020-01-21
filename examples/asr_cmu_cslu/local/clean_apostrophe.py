import os
import sys
import fire
from typing import *

def main(text_file: str,
         out_file: str, 
         quote_file: str = "apostrophe_words"):
    word_quote = set()
    with open(quote_file, 'r') as fp:
        for word in fp:
            word = word.strip().split()[0]
            if '(' in word:
                continue
            else:
                word_quote.add(word.upper())
    with open(text_file, 'r') as fpr:
        with open(out_file, 'w+') as fpw:
            for line in fpr:
                toks = line.strip().split()
                for i in range(1, len(toks)):
                    t = toks[i].replace('.', '')
                    if "'" in t and t not in word_quote:
                        # print(toks[0], t)
                        t = t.replace("'", "")
                    toks[i] = t
                fpw.write(' '.join(toks) + "\n")
    

if __name__ == '__main__':
    fire.Fire(main)
