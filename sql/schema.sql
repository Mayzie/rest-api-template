BEGIN TRANSACTION;

	DROP SCHEMA IF EXISTS TMP CASCADE;
	
	CREATE SCHEMA TMP;

	CREATE EXTENSION IF NOT EXISTS hstore;
	CREATE EXTENSION IF NOT EXISTS pgcrypto CASCADE;
	-- CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
	
	CREATE TYPE TMP.LOGINTYPE AS ENUM (
		'phone',
		'email'
	);

	CREATE TYPE TMP.PERMISSION AS ENUM (
		'create',
		'read',
		'update',
		'delete'
	);

	CREATE TYPE TMP.LANGUAGE AS ENUM (
		'en'
	);

	CREATE TABLE TMP.Objects (
		ObjectID	UUID,
		Created		TIMESTAMP WITH TIME ZONE,
		Updated		TIMESTAMP WITH TIME ZONE,
		---
		PRIMARY KEY (ObjectID)
	);
	
	CREATE TABLE TMP.Users (
		Name		TEXT,
		Data		HSTORE,
		---
		PRIMARY KEY (ObjectID)
	) INHERITS (TMP.Objects);

	CREATE TABLE TMP.UserIdentities (
		UserID		UUID,
		LoginType	TMP.LOGINTYPE,
		Identifier	TEXT,
		Password	TEXT,
		---
		FOREIGN KEY (UserID) REFERENCES TMP.Users (ObjectID) ON DELETE CASCADE,
		PRIMARY KEY (UserID, Identifier, LoginType)
	);

	CREATE UNIQUE INDEX useridentities_identkey
		ON TMP.UserIdentities (Identifier, LoginType);

	CREATE UNIQUE INDEX useridentities_uniqlogon
		ON TMP.UserIdentities (UserID, LoginType);	-- Permit only one login type per user.

	CREATE TABLE TMP.UserPermissions (
		UserID		UUID,
		TargetObjectID	UUID,
		Permission	TMP.PERMISSION,
		---
		FOREIGN KEY (UserID) REFERENCES TMP.Users (ObjectID) ON DELETE CASCADE,
		PRIMARY KEY (UserID, TargetObjectID, Permission)
	);

	CREATE TABLE TMP.UserTokens (
		UserID		UUID,
		Token		TEXT,
		Expires		TIMESTAMP WITH TIME ZONE	NOT NULL,
		---
		FOREIGN KEY (UserID) REFERENCES TMP.Users (ObjectID) ON DELETE CASCADE
	);

	-- SELECT create_hypertable('TMP.usertokens', 'expires');	-- TimescaleDB

COMMIT;