SET SCHEMA 'inventory';

ALTER TABLE customers REPLICA IDENTITY DEFAULT;
ALTER TABLE customers ADD COLUMN biography TEXT;
ALTER TABLE customers ALTER COLUMN biography SET STORAGE EXTERNAL;
ALTER TABLE customers ADD COLUMN updated_at TIMESTAMP;
ALTER TABLE customers ADD COLUMN updated_at_2 TIMESTAMP default now();

CREATE EXTENSION IF NOT EXISTS moddatetime;
CREATE TRIGGER updated_at_customers
    BEFORE UPDATE ON customers
    FOR EACH ROW
    EXECUTE PROCEDURE moddatetime(updated_at);

create table debezium_signals(
    id   varchar(42) default gen_random_uuid() not null primary key,
    type varchar(32) not null,
    data varchar(2048)
);

UPDATE customers set biography = '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';

ALTER TABLE products REPLICA IDENTITY DEFAULT;
ALTER TABLE products ADD COLUMN instructions TEXT;
ALTER TABLE products ALTER COLUMN instructions SET STORAGE EXTERNAL;

UPDATE products set instructions = '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';
