-- make perf-push が INSERT する 3 テーブル (中身は make measure の結果)。bench = ベンチ実行時の unix time (UTC) が JOIN キー
CREATE DATABASE IF NOT EXISTS isucon;

CREATE TABLE IF NOT EXISTS isucon.results (
    bench  DateTime,
    score  UInt64,
    commit String,
    note   String
) ENGINE = MergeTree ORDER BY bench;

-- 列順は tools/alp.yaml の output と一致させる
CREATE TABLE IF NOT EXISTS isucon.alp (
    bench  DateTime,
    count  UInt64,
    c_2xx  UInt64,
    c_4xx  UInt64,
    c_5xx  UInt64,
    method LowCardinality(String),
    uri    String,
    sum    Float64,
    avg    Float64,
    p90    Float64,
    max    Float64
) ENGINE = MergeTree ORDER BY (bench, sum);

CREATE TABLE IF NOT EXISTS isucon.slow (
    bench         DateTime,
    fingerprint   String,
    cnt           UInt64,
    qtime_sum     Float64,
    qtime_avg     Float64,
    rows_examined Float64
) ENGINE = MergeTree ORDER BY (bench, qtime_sum);

-- otelcol の clickhouse exporter が otel_metrics_* / otel_traces を作る先
CREATE DATABASE IF NOT EXISTS otel;
