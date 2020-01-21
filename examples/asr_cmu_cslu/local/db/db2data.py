import os
import sys
import fire
import shutil
import sqlite3
import functools
from typing import *

utt_based_files = ['wav.scp', 'text', 'utt2spk', 'feats.scp']
spk_based_files = ['spk2gender', 'cmvn.scp']

utt_col2file = {
    'wav': 'wav.scp',
    'script': 'text',
    'spk_id': 'utt2spk',
    'feats': 'feats.scp',
    'hires_feat': 'hires_feat',
    'corpus': 'corpus',
    'split_by_utt': 'split_by_utt'
}
spk_col2file = {
    'gender': 'spk2gender',
    'cmvn': 'cmvn.scp',
    'hires_cmvn': 'hires_cmvn',
    'split_by_spk': 'split_by_spk',
}


def remove_empty_files(data_dir: str) -> None:
    """
    Removes empty files in given directory
    :param data_dir: full path to directory
    :return: None
    """
    for f in os.listdir(data_dir):
        full_path = os.path.join(data_dir, f)
        if os.path.isfile(full_path) and os.stat(full_path).st_size  == 0:
            os.remove(full_path)


def file_check(data_dir: str,
               files: List[str]) -> None:
    """
    Moves exists files to .backup
    :param data_dir: exist data directory to be checked
    :param files: files to check
    :return: None
    """
    if os.path.exists(data_dir):
        exist_files = [
            os.path.join(data_dir, f)
            for f in files
            if os.path.exists(os.path.join(data_dir, f))
        ]
        if len(exist_files) > 0:
            if not os.path.exists(os.path.join(data_dir, '.backup')):
                print(f"Backup folder does not exist. Creating {data_dir}/.backup")
                try:
                    os.mkdir(os.path.join(data_dir, '.backup'))
                except OSError as e:
                    print(f"Cannot create backup directory in {data_dir}\n{e}")
                    sys.exit(1)
            for f in exist_files:
                try:
                    shutil.copyfile(f, f"{data_dir}/.backup/{os.path.basename(f)}")
                    print(f"Moved {f} to {data_dir}/.backup")
                except Exception as e:
                    print(f"Failed to move file {f} to {data_dir}/.backup\n{e}")
                    sys.exit(1)
    else:
        print(f"{data_dir} does not exist. Creating {data_dir}")
        try:
            os.mkdir(data_dir)
        except OSError as e:
            print(f"Cannot create {data_dir}\n{e}")
            sys.exit(1)


def query2data(*, db: str,
               query: str,
               id_type: str,
               data_dir: str,
               hires_dir: str) -> None:
    """
    Write results of query into kaldi-style data dir
    :param db: db file
    :param query: SQL query to execute
    :param id_type: indexed by 'spk' or 'utt'
    :param data_dir: output data dir
    :param hires_dir: output hires data dir
    :return:
    """
    if id_type == 'spk':
        files = spk_based_files
        col2file = spk_col2file
        hires_col = 'hires_cmvn'
        hires_file = 'cmvn.scp'
    elif id_type == 'utt':
        files = utt_based_files
        col2file = utt_col2file
        hires_col = 'hires_feats'
        hires_file = 'feats.scp'
    else:
        print(f"Unrecognized id type: {id_type}")
        sys.exit(1)
    id_col = f"{id_type}_id"

    try:
        conn = sqlite3.connect(db)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
    except sqlite3.Error as e:
        print(f"Filed to connect to database {db}\n{e}")
        sys.exit(1)

    try:
        res = cursor.execute(query)
    except sqlite3.Error as e:
        print(f"Filed to execute query:\n\t{query}\n{e}")
        sys.exit(1)

    handlers = {f: open(os.path.join(data_dir, f), 'w+') for f in files}
    if hires_dir is not None:
        hires_handlers = {f: open(os.path.join(hires_dir, f), 'w+') for f in files}
        hires_handlers[hires_col] = open(os.path.join(hires_dir, hires_file), 'w+')
        if 'feats.scp' in hires_handlers:
            hires_handlers.pop('feats.scp')
        if 'cmvn.scp' in hires_handlers:
            hires_handlers.pop('cmvn.scp')
    for row in res:
        for col in row.keys():
            if col == id_col or col not in col2file:
                continue
            if col2file[col] in handlers and row[col] is not None:
                handlers[col2file[col]].write(f"{row[id_col]} {row[col]}\n")
            if hires_dir is not None and col2file[col] in hires_handlers and row[col] is not None:
                hires_handlers[col2file[col]].write(f"{row[id_col]} {row[col]}\n")
    cursor.close()
    conn.close()
    for k, f in handlers.items():
        f.close()
    remove_empty_files(data_dir)

    if hires_dir:
        for k, f in hires_handlers.items():
            f.close()
        remove_empty_files(hires_dir)


def db2data(*, db: str,
            out_dir: str,
            hires: bool = False,
            hires_dir: str = None,
            corpus: str = None,
            assignment: str = None,
            split_by: str = None):
    """
    Extract data from db and write as kaldi-style data dir
    :param db: db file
    :param out_dir: output data directory
    :param hires: will write hires data directory if set
    :param hires_dir: output hires data dir
    :param corpus: choose data from corpus
    :param assignment: choose certain subset, such as 'train', 'test', etc.
    :param split_by: subset split by 'spk' or 'utt'
    :return: None
    """
    if hires is True and hires_dir is None:
        print(f"hires_dir is required when hires is True")
        sys.exit(1)
    if hires is False:
        hires_dir = None

    if assignment is not None:
        if split_by != 'spk' and split_by != 'utt':
            print(f"split_by should be either spk or utt")
            sys.exit(1)

    if assignment is not None and split_by == 'spk':
        utt_query = "SELECT * FROM utterances NATURAL JOIN (SELECT spk_id, split_by_spk FROM speakers)"
    else:
        utt_query = "SELECT * FROM utterances"

    if assignment is not None and split_by == 'utt':
        if corpus is not None:
            spk_query = "SELECT * FROM speakers NATURAL JOIN (SELECT spk_id, split_by_utt, corpus FROM utterances)"
        else:
            spk_query = "SELECT * FROM speakers NATURAL JOIN (SELECT spk_id, split_by_utt FROM utterances)"
    else:
        if corpus is not None:
            spk_query = "SELECT * FROM speakers NATURAL JOIN (SELECT spk_id, split_by_utt, corpus FROM utterances)"
        else:
            spk_query = "SELECT * FROM speakers NATURAL JOIN (SELECT spk_id, split_by_utt FROM utterances)"

    where_clauses = []
    if corpus is not None:
        where_clauses.append(f"corpus='{corpus}'")
    if assignment is not None:
        where_clauses.append(f"split_by_{split_by}='{assignment}'")
    if where_clauses:
        utt_query += " WHERE " + ' AND '.join(where_clauses)
        spk_query += " WHERE " + ' AND '.join(where_clauses)
    utt_query += ";"
    spk_query += ";"

    file_check(out_dir, spk_based_files + utt_based_files)
    if hires_dir is not None:
        file_check(hires_dir, spk_based_files + utt_based_files)

    query2data(db=db,
               query=utt_query,
               id_type='utt',
               data_dir=out_dir,
               hires_dir=hires_dir)
    query2data(db=db,
               query=spk_query,
               id_type='spk',
               data_dir=out_dir,
               hires_dir=hires_dir)


if __name__ == '__main__':
    fire.Fire(db2data)
