{% snapshot customers_snapshot %}

{{
    config(
      target_database='sinkdb',
      target_schema='snapshots',
      unique_key='id',
      strategy='timestamp',
      updated_at='updated_at_new'
    )
}}

SELECT
  *,
  TO_TIMESTAMP(updated_at/1000000.0) as updated_at_new,
  now() AS SNAPSHOT_DATE
FROM {{ source('inventorysink', 'customers') }}
{% if is_incremental() %}
  -- this filter will only be applied on an incremental run
where source_ts_ms > (select max(source_ts_ms) from {{ this }})
{% endif %}
{% endsnapshot %}