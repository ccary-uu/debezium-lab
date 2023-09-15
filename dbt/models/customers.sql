{{
    config(
        materialized='incremental'
    )
}}


SELECT distinct on(id, updated_at)
    id,
    CONCAT(id, updated_at) as id_and_updated_at,
    first_name,
    last_name,
    email,
    --customer_type,
    __deleted,
    __lsn,
    __op,
    TO_TIMESTAMP(__source_ts_ms/1000.0) AS source_ts_ms,
    TO_TIMESTAMP(updated_at/1000000.0) AS updated_at,
    now() AS ETL_DATE
FROM {{ source('inventorysink', 'customers') }}
order by id, updated_at, source_ts_ms DESC, __lsn DESC
{% if is_incremental() %}
  -- this filter will only be applied on an incremental run
  where source_ts_ms > (select max(source_ts_ms) from {{ this }})
{% endif %}