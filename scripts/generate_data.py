#!/usr/bin/env python3
"""
随机数据生成脚本
生成符合test_local表结构的随机数据，输出为TabSeparated格式
"""
import random
import string
from datetime import datetime, timedelta
import sys


def generate_batch(batch_size: int = 100000) -> None:
    """
    生成一批随机数据，输出为TabSeparated格式到stdout

    Args:
        batch_size: 生成的数据行数
    """
    base_time = datetime.now()
    event_types = ['click', 'view', 'purchase', 'login']

    for _ in range(batch_size):
        id_val = random.randint(1, 10**18)
        # 随机分配到不同小时，以产生多个分区
        event_time = base_time - timedelta(hours=random.randint(0, 23))
        user_id = random.randint(1, 1000000)
        event_type = random.choice(event_types)
        value = round(random.uniform(0, 10000), 2)
        status = random.randint(0, 255)
        description = ''.join(random.choices(string.ascii_letters, k=50))
        metadata = '{}'
        created_at = base_time.strftime('%Y-%m-%d %H:%M:%S')
        updated_at = created_at

        # 输出TabSeparated格式
        print(f"{id_val}\t{event_time.strftime('%Y-%m-%d %H:%M:%S')}\t{user_id}\t{event_type}\t{value}\t{status}\t{description}\t{metadata}\t{created_at}\t{updated_at}")


def main():
    """主函数"""
    batch_size = int(sys.argv[1]) if len(sys.argv) > 1 else 100000
    generate_batch(batch_size)


if __name__ == '__main__':
    main()
