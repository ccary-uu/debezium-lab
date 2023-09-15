{% snapshot customers_diff_snapshot %}

{{
    config(
      target_database='sinkdb',
      target_schema='snapshots',
      unique_key='id',
      strategy='check',
      check_cols=['first_name', 'last_name', 'email','customer_type', '__deleted'],
      updated_at='TO_TIMESTAMP(updated_at/1000000.0)'
    )
}}

SELECT
  *,
  now() AS SNAPSHOT_DATE
FROM {{ source('inventorysink', 'customers') }}
--ORDER BY id, updated_at, source_ts_ms DESC, __lsn DESC
{% if is_incremental() %}
  -- this filter will only be applied on an incremental run
  where source_ts_ms > (select max(source_ts_ms) from {{ this }})
{% endif %}
{% endsnapshot %}