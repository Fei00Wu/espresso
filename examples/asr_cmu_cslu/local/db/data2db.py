import os
import sys
import fire
import sqlite3
from typing import *

utt_based_files = ['wav.scp', 'text', 'utt2spk', 'feats.scp']
spk_based_files = ['spk2gender', 'cmvn.scp']
utt_file2col = {
    'wav.scp': 'wav',
    'text': 'script',
    'utt2spk': 'spk_id',
    'feats.scp': 'feats'
}
spk_file2col = {
    'spk2gender': 'gender',
    'cmvn.scp': 'cmvn'
}


def check_files(data_dir: str):
    return any(os.path.exists(os.path.join(data_dir, f)) for f in utt_based_files) \
           and any(os.path.exists(os.path.join(data_dir, f)) for f in spk_based_files)


def write_db(*, id_type: str,
             data_dir: str,
             db_file: str,
             schema: str = None,
             hires_dir: str = None,
             corpus: str = '',
             id2assignment: Dict[str, str] = {}, 
             gen_csv: bool = False):
    if id_type == 'utt':
        file_list = utt_based_files
        cols = ['utt_id', 'corpus', 'split_by_utt']
        file2col = utt_file2col
        hires_file = 'feats.scp'
        hires_col = 'hires_feat'
        tbl = 'UTTERANCES'
        if gen_csv:
            csv_file = os.path.join(data_dir, 'utt.csv')
    elif id_type == 'spk':
        file_list = spk_based_files
        cols = ['spk_id', 'split_by_spk']
        file2col = spk_file2col
        hires_file = 'cmvn.scp'
        hires_col = 'hires_cmvn'
        tbl = 'SPEAKERS'
        if gen_csv:
            csv_file = os.path.join(data_dir, 'spk.csv')
    else:
        print(f"Unknown id type: {id_type}")
        sys.exit(1)

    try:
        conn = sqlite3.connect(db_file)
        cursor = conn.cursor()
        if schema is not None:
            q = open(schema, 'r').read()
            sqlite3.complete_statement(q)
            cursor.executescript(q)
    except sqlite3.Error as e:
        print(f"Error when creating tables:\n {str(e)}")
        sys.exit(1)

    files = []
    for f in file_list:
        if os.path.exists(os.path.join(data_dir, f)):
            cols.append(file2col[f])
            files.append(os.path.join(data_dir, f))

    if hires_dir is not None \
            and os.path.exists(os.path.join(hires_dir, hires_file)):
        cols.append(hires_col)
        files.append(os.path.join(hires_dir, hires_file))
   
    if gen_csv:
        csv_fp = open(csv_file, 'w+')
        csv_fp.write(','.join(cols + ['\n']))
    handlers = [open(f, 'r') for f in files]
    num_vals = len(cols)
    place_holder = ["?" for _ in range(num_vals)]
    template = f"INSERT OR IGNORE INTO {tbl}({','.join(cols)}) VALUES({','.join(place_holder)})"
    try:
        for lines in zip(*handlers):
            toks = [l.strip().split() for l in lines]
            if id_type == 'utt':
                vals = [f"{toks[0][0]}", f"{corpus}"]
            else:
                vals = [f"{toks[0][0]}"]
            id = toks[0][0]
            if id in id2assignment:
                vals.append(id2assignment[id])
            else:
                vals.append(f"unassigned")
            vals.extend([f"{' '.join(t[1:])}" for t in toks])
            cursor.execute(template, vals)
            if gen_csv:
                csv_fp.write(','.join(vals + ['\n']))
        conn.commit()
        cursor.close()
        conn.close()
        if gen_csv:
            csv_fp.close()
        for f in handlers:
            f.close()
    except sqlite3.Error as e:
        print(str(e), vals)
        sys.exit(1)


def get_assignments(files: Dict[str, str]) -> Dict[str, str]:
    assignment = {}
    for f_type, file in files.items():
        with open(file, 'r') as fp:
            for line in fp:
                assignment[line.strip().split()[0]] = f_type
    return assignment


def get_id_file(dir: str,
                split_by_utt: bool) -> Optional[str]:
    candidate_files = utt_based_files if split_by_utt else spk_based_files
    for f in candidate_files:
        if os.path.exists(os.path.join(dir, f)):
            return os.path.join(dir, f)
    return None


def main(*, data_dir: str,
         hires_dir: str = None,
         corpus: str = None,
         db_file: str = None,
         schema: str = None,
         train_dir: str = None,
         test_dir: str = None,
         dev_dir: str = None,
         split_by_utt: bool = False,
         gen_csv: bool = False) -> None:
    """
    Converts a Kaldi data directory to a db file for sqlite3
    :param data_dir: expect at least one utt-based and one spk-based file to exist
    :param hires_dir: expect hires_dir/feats.scp to exist
    :param corpus: will be the basename of data_dir if not specified
    :param db_file: full path to where .db file sits. Default to be in data_dir
    :param schema: path to db schema
    :param train_dir: handle data_dir that is already split. Not required.
    :param test_dir: same as above
    :param dev_dir: same as above
    :param split_by_utt: split by utt or spk, default to be split by spk
    :param gen_csv: generate utt.csv and spk.csv file
    :return:
    """

    if hires_dir is None:
        hires_dir = f"{data_dir}_hires"

    if os.path.exists(hires_dir):
        get_hires = True
    else:
        get_hires = False
        print("Warning: hires dir does not exit")

    if corpus is None:
        corpus = os.path.basename(data_dir)

    if db_file is None:
        db_file = os.path.join(data_dir, f"{corpus}.db")
        if os.path.exists(db_file):
            print(f"{db_file} already exists. Will not override exit records.")

    if not check_files(data_dir):
        print(f"Expect at least one utt-based file and one speaker-based file to exist in {data_dir}")
        sys.exit(1)

    assignment_file = {}

    if train_dir is not None:
        id_file = get_id_file(train_dir, split_by_utt)
        if id_file is None:
            print(f"No id_file found in {train_dir}. Ignore {train_dir}.")
        else:
            assignment_file['train'] = id_file

    if dev_dir is not None:
        id_file = get_id_file(dev_dir, split_by_utt)
        if id_file is None:
            print(f"No id_file found in {dev_dir}. Ignore {dev_dir}.")
        else:
            assignment_file['dev'] = id_file

    if test_dir is not None:
        id_file = get_id_file(test_dir, split_by_utt)
        if id_file is None:
            print(f"No id_file found in {test_dir}. Ignore {test_dir}.")
        else:
            assignment_file['test'] = id_file

    id2assignment = get_assignments(assignment_file) if assignment_file else {}
    write_db(id_type='utt',
             data_dir=data_dir,
             db_file=db_file,
             schema=schema,
             hires_dir=hires_dir,
             corpus=corpus,
             id2assignment=id2assignment, 
             gen_csv=gen_csv)
    write_db(id_type='spk',
             data_dir=data_dir,
             db_file=db_file,
             schema=None,
             hires_dir=hires_dir,
             corpus=corpus,
             id2assignment=id2assignment,
             gen_csv=gen_csv)


if __name__ == '__main__':
    fire.Fire(main)
