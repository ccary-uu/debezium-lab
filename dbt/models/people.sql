{{
    config(
        materialized='incremental'
    )
}}


select * from {{ ref("customers") }}