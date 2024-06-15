﻿START TRANSACTION;

CREATE TABLE consumer_messages (
    id text NOT NULL,
    created_at bigint NOT NULL,
    available_after bigint NOT NULL,
    attempts integer NOT NULL,
    consumer_type text NOT NULL,
    payload_type text NOT NULL,
    payload text NOT NULL,
    insert_id text NOT NULL,
    CONSTRAINT "PK_consumer_messages" PRIMARY KEY (id)
);

CREATE TABLE poisoned_messages (
    id text NOT NULL,
    created_at bigint NOT NULL,
    available_after bigint NOT NULL,
    attempts integer NOT NULL,
    consumer_type text NOT NULL,
    payload_type text NOT NULL,
    payload text NOT NULL,
    insert_id text NOT NULL,
    CONSTRAINT "PK_poisoned_messages" PRIMARY KEY (id)
);

CREATE TABLE scheduled_messages (
    id text NOT NULL,
    tag text,
    available_after bigint NOT NULL,
    chron_expression text NOT NULL,
    chron_timezone text NOT NULL,
    payload_type text NOT NULL,
    payload text NOT NULL,
    CONSTRAINT "PK_scheduled_messages" PRIMARY KEY (id)
);

CREATE TABLE submitted_values (
    "Id" integer GENERATED BY DEFAULT AS IDENTITY,
    value double precision NOT NULL,
    CONSTRAINT "PK_submitted_values" PRIMARY KEY ("Id")
);

CREATE UNIQUE INDEX "IX_consumer_messages_insert_id_consumer_type" ON consumer_messages (insert_id, consumer_type);

COMMIT;

