{% snapshot customers_snapshot %}

{{
    config(
      target_database='sinkdb',
      target_schema='snapshots',
      unique_key='id',
      strategy='timestamp',
      updated_at='source_ts_ms',
      full_refresh=true
    )
}}

SELECT DISTINCT ON (id, __source_ts_ms)
  id,
  first_name,
  last_name,
  email,
  phone_numbers,
  __deleted,
  __lsn,
  __op,
  TO_TIMESTAMP(__source_ts_ms/1000.0) AS source_ts_ms,
  now() AS ETL_DATE
FROM {{ source('inventorysink', 'customers') }}
{% if is_incremental() %}
  -- this filter will only be applied on an incremental run
  where source_ts_ms > (select max(source_ts_ms) from {{ this }})
{% endif %}
ORDER BY id, __source_ts_ms, __lsn DESC

{% endsnapshot %}