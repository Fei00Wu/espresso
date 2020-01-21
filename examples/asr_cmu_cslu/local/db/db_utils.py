import sys
import fire
import random
import sqlite3
import numpy as np
from typing import *
import heapq

spk_cols = {'cmvn', 'hires_cmvn', 'gender', 'split_by_spk'}
utt_cols = {'spk', 'wav', 'feats', 'text', 'hires_feat', 'split_by_utt'}

random.seed(3)
np.random.seed(3)


# TODO: Fill this in !
def even_split(*, num_splits: int,
               split_by: str = 'spk',
               constrain_on: str = 'words') -> None:
    """
    Evenly splits data set into subsets by 'spk' or 'utt'
    constrain on number of words in text or duration (requires reco2dur)
    :param num_splits: number of subsets
    :param split_by: 'spk' or 'utt'
    :param constrain_on: 'word' or duration
    :return: None
    """
    pass


def _split_rate_to_acc_rate(split_rate: 'np.ndarray') -> 'np.ndarray':
    acc_rate = [split_rate[0]]
    prev = split_rate[0]
    for r in split_rate[1:]:
        acc_rate.append(r + prev)
        prev += r
    return np.array(acc_rate)


def random_split(*subsets: List[Tuple[str, float]],
                 db_file: str,
                 split_by: str) -> None:
    """

    :param subsets:
    :param db_file:
    :param split_by:
    :return:
    """

    print(subsets)
    ratio = [s[1] for s in subsets]
    names = [s[0] for s in subsets]

    if len(ratio) != len(names):
        print(f"Length of ration and length of names "
              f"are not the same:\nratio\t{ratio}\nnames\t{names}")
        sys.exit(1)
    if split_by == 'spk':
        table = "SPEAKERS"
    elif split_by == 'utt':
        table = "UTTERANCES"
    else:
        print(f"Cannot split by {split_by}")
        sys.exit(1)
    id_col = split_by + "_id"
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    all_id = [row[0] for row in cursor.execute(f"SELECT {id_col} FROM {table};")]
    num_id = len(all_id)

    num_splits = len(ratio)
    np_ratio = np.array(ratio)
    np_ratio /= np.sum(np_ratio)
    acc_rate = _split_rate_to_acc_rate(ratio).reshape([-1, 1])

    rand_res = np.random.rand(num_id)
    rand_res = rand_res.reshape([1, -1])

    acc_rate = np.repeat(acc_rate, num_id, 1)  # [num_splits, num_id]
    rand_res = np.repeat(rand_res, num_splits, 0)  # [num_splits, num_id]
    mask = np.where(rand_res <= acc_rate, 1.0, 0.0)  # [num_splits, num_id]

    category = np.arange(num_splits, 0, -1).reshape(-1, 1)
    category = np.repeat(category, num_id, 1)

    assignments = np.argmax(mask * category, 0)  # [num_id]
    assignments = assignments.tolist()

    query_template = f"UPDATE {table} SET split_by_{split_by} = ? WHERE {id_col} = ?"
    for id, assign in zip(all_id, assignments):
        try:
            cursor.execute(query_template, (names[int(assign)], id))
        except sqlite3.Error as e:
            print(f"Failed to add assignment to {id}:\n{str(e)}")
    conn.commit()
    cursor.close()
    conn.close()


def update(db_file: str,
           tbl: str,
           col: str,
           data_file: str) -> None:
    """
    Updates exist .db file from given kaldi style data file
    :param db_file: Exist data file
    :param tbl: table to update
    :param col: column to update
    :param data_file: data file used to update db
    :return: None
    """
    if tbl.upper() != "SPEAKERS" and tbl.upper != "UTTERANCES":
        print(f"Table {tbl} does not exist")
        sys.exit(1)
    id_col = "spk_id" if tbl.upper() == "SPEAKERS" else "utt_id"
    query_template = f"UPDATE {tbl} SET {col} = ? WHERE {id_col} = ?"

    try:
        conn = sqlite3.connect(db_file)
        cursor = conn.cursor()
    except sqlite3.Error as e:
        print(f"Cannot connect to {db_file}:\n{e}")
        sys.exit(1)

    with open(data_file, 'r') as fp:
        for line in fp:
            toks = line.strip().split()
            id = toks[0]
            content = ' '.join(toks[1:])
            cursor.execute(query_template, (content, id))

    conn.commit()
    cursor.close()
    conn.close()


if __name__ == '__main__':
    fire.Fire({
        'update': update,
        'random_split': random_split,
        'even_split': even_split
    })
