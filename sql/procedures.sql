BEGIN TRANSACTION;

	-- Generate a new random, secure token, used for user authentication.
	CREATE OR REPLACE FUNCTION GenerateToken() RETURNS VARCHAR(64) AS $$
	BEGIN
		RETURN substr(encode(gen_random_bytes(48), 'base64'), 0, 65);
	END;
	$$ LANGUAGE plpgsql STABLE;

	-- Checks whether any of the elements in AElements exists inside of AArray.
	CREATE OR REPLACE FUNCTION InArray(
		AArray ANYARRAY,
		VARIADIC AElements ANYARRAY
	) RETURNS BOOLEAN AS $$
	DECLARE
		I	INTEGER;
	BEGIN
		FOR I IN
			array_lower(AElements, 1)
			..
			array_upper(AElements, 1)
		LOOP
			IF (array_position(AArray, AElements[I]) IS NOT NULL) THEN
				RETURN TRUE;
			END IF;
		END LOOP;

		RETURN FALSE;
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;

	-- Converts a UUID string to a friendlier, compressed string (compatible with
	-- the from_uuid() function in the Python template file common.py).
	CREATE OR REPLACE FUNCTION FromUUID(
		AUUID	UUID,
		OUT OUUID	TEXT
	) RETURNS TEXT AS $$
	BEGIN
		OUUID := translate(encode(decode(replace(AUUID::TEXT, '-', ''), 'hex'), 'base64'), '+/=', '-_');
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;

	-- Creates and inserts a new object into the database table, ATableName, with
	-- fields, AVals. The table MUST inherit from the generic Objects table
	-- defined within the schema.
	--
	-- Usage: CreateObject('users', 'name', 'Jean Luc Picard');
	CREATE OR REPLACE FUNCTION TMP.CreateObject (
		ATableName	TEXT,
		VARIADIC AVals	TEXT[],
		--
		OUT OObjectID	UUID
	) RETURNS UUID AS $$
	DECLARE
		VFields		TEXT[];
		VValues		TEXT[];
		I		INTEGER;
		VFieldType	TEXT;
		VNextType	TEXT;
	BEGIN
		FOR I IN
			array_lower(AVals, 1)
			..
			array_upper(AVals, 1)
		LOOP
			IF(I % 2 = 1) THEN
				-- Check that the field exists within the specified table.
				SELECT 
					data_type 
					INTO VFieldType
					FROM
						information_schema.columns
					WHERE
						table_schema = 'tmp'	-- ToDo: Change schema
						AND table_name = lower(ATableName)
						AND column_name = lower(AVals[I]);

				IF NOT (FOUND) THEN
					RAISE EXCEPTION 'Column "%" does not exist in table "%".', AVals[I], ATableName;
				END IF;

				-- Check if the value can be represented as-is (numbers, boolean, etc), whether
				-- it needs to be enclosed in quotations, or any other special format.
				VNextType := NULL;
				IF(InArray(ARRAY['smallint', 'integer', 'bigint', 'decimal', 'numeric', 'real', 'double precision', 'boolean', 'ARRAY'], VFieldType)) THEN
					VNextType := 'NUM';
				ELSIF(InArray(ARRAY['interval'], VFieldType)) THEN
					VNextType := 'INTERVAL';
				END IF;
				
				VFields := VFields || AVals[I];
			ELSE
				IF(VNextType = 'NUM') THEN
					VValues := VValues || AVals[I];	-- Leave as-is
				ELSIF(VNextType = 'INTERVAL') THEN
					VValues := VValues || ('INTERVAL ''' || AVals[I] || '''');  -- Enclose in INTERVAL '{}'
				ELSE
					VValues := VValues || ('''' || AVals[I] || '''');  -- Enclose in quotation marks
				END IF;
			END IF;
		END LOOP;

		IF (array_length(VFields, 1) != array_length(VValues, 1)) THEN
			RAISE EXCEPTION 'Values array does not split evenly.';
		END IF;

		-- ToDo: Change schema.
		EXECUTE format('INSERT INTO TMP.%I (ObjectID, Created, Updated, %s) VALUES (''{%s}'', ''%s'', ''%s'', %s) RETURNING ObjectID;', 
			ATableName,
			array_to_string(VFields, ','), 
			gen_random_uuid(),  -- Object ID
			NOW(),  -- Created
			NOW(),  -- Updated
			array_to_string(VValues, ',')
		) INTO OObjectID;
	END;
	$$ LANGUAGE plpgsql VOLATILE;

	-- Updates an existing object within a table inherited from Objects.
	-- Similar to CreateObject (above).
	--
	-- Usage: UpdateObject('users', 'name = ''Jean Luc Picard''', 'name',
	--        'Jack O''Neill');
	-- (finds users with the name 'Jean Luc Picard' and changes it to
	-- Jack O'Neill (with two L's)).
	CREATE OR REPLACE FUNCTION TMP.UpdateObject (
		ATableName	TEXT,
		AWhereClause	TEXT,
		VARIADIC AVals	TEXT[]
	) RETURNS VOID AS $$
	DECLARE
		VFields		TEXT[];
		VValues		TEXT[];
		I		INTEGER;
		VUpdateStr	TEXT;
		VFieldType	TEXT;
		VNextType	TEXT;
	BEGIN
		VUpdateStr := 'UPDATE TMP.%I SET Updated = NOW(), ';	-- ToDo: Change schema.
		FOR I IN
			array_lower(AVals, 1)
			..
			array_upper(AVals, 1)
		LOOP
			IF(I % 2 = 1) THEN
				-- Check that the field exists within the specified table.
				SELECT 
					data_type 
					INTO VFieldType
					FROM
						information_schema.columns
					WHERE
						table_schema = 'tmp'	-- ToDo: Change schema.
						AND table_name = lower(ATableName)
						AND column_name = lower(AVals[I]);

				IF NOT (FOUND) THEN
					RAISE EXCEPTION 'Column "%" does not exist in table "%".', AVals[I], ATableName;
				END IF;

				-- Check if the value can be represented as-is (numbers, boolean, etc), whether
				-- it needs to be enclosed in quotations, or any other special format.
				VNextType := NULL;
				IF(InArray(ARRAY['smallint', 'integer', 'bigint', 'decimal', 'numeric', 'real', 'double precision', 'boolean', 'ARRAY'], VFieldType)) THEN
					VNextType := 'NUM';
				ELSIF(InArray(ARRAY['interval'], VFieldType)) THEN
					VNextType := 'INTERVAL';
				END IF;

				VFields := VFields || AVals[I];

				VUpdateStr := VUpdateStr || AVals[I] || ' = ';
			ELSE
				VValues := VValues || AVals[I];
				
				IF(VNextType = 'NUM') THEN
					VUpdateStr := VUpdateStr || AVals[I];	-- Leave as-is
				ELSIF(VNextType = 'INTERVAL') THEN
					VUpdateStr := VUpdateStr || ('INTERVAL ''' || AVals[I] || '''');  -- Enclose in INTERVAL '{}'
				ELSE
					VUpdateStr := VUpdateStr || ('''' || AVals[I] || '''');  -- Enclose in quotation marks
				END IF;

				IF (I != array_upper(AVals, 1)) THEN
					-- If there are still more fields to update, append a comma.
					VUpdateStr := VUpdateStr || ', ';
				END IF;
			END IF;
		END LOOP;

		IF (array_length(VFields, 1) != array_length(VValues, 1)) THEN
			RAISE EXCEPTION 'Values array does not split evenly.';
		END IF;

		VUpdateStr := format(VUpdateStr, ATableName) || ' WHERE ' || AWhereClause;

		EXECUTE VUpdateStr;
	END;
	$$ LANGUAGE plpgsql VOLATILE;

	-- Retrieves the users information needed for logging in.
	CREATE OR REPLACE FUNCTION TMP.GetUserDetails (
		AIdentifier	TEXT,
		--
		OUT OUserID		UUID,
		OUT OPassword		TEXT,
		OUT OLoginType		TEXT,
		OUT OCreated		TIMESTAMP WITH TIME ZONE,
		OUT OUpdated		TIMESTAMP WITH TIME ZONE,
		OUT OName		TEXT,
		OUT OData		HSTORE
	) RETURNS RECORD AS $$
	DECLARE
		VUserRecord		RECORD;
		VTableName		TEXT;
	BEGIN
		SELECT 
			ui.UserID, ui.Password, ui.LoginType::TEXT, Created, Updated, Name, Data
			INTO
			OUserID, OPassword, OLoginType, OCreated, OUpdated, OName, OData
			FROM
				TMP.UserIdentities ui
			INNER JOIN
				TMP.Users u ON ui.UserID = u.ObjectID
			WHERE
				Identifier = AIdentifier;

		IF NOT (FOUND) THEN
			RAISE EXCEPTION 'user_not_found';
		END IF;	
	END;
	$$ LANGUAGE plpgsql STABLE;

	-- Generates a new authentication token for the user.
	CREATE OR REPLACE FUNCTION TMP.UserLogin (
		AUserID		UUID,
		--
		OUT OToken	TEXT,
		OUT OExpires	TIMESTAMP WITH TIME ZONE
	) RETURNS RECORD AS $$
	BEGIN		
		INSERT INTO TMP.UserTokens (
			UserID, Token, Expires
		) VALUES (
			AUserID, GenerateToken(), NOW() + INTERVAL '1 month'
		) RETURNING
			Token, Expires
			INTO
			OToken, OExpires;
	END;
	$$ LANGUAGE plpgsql VOLATILE;

	-- Deletes a users authentication token.
	CREATE OR REPLACE FUNCTION TMP.UserLogout (
		AUserID		UUID,
		AToken		TEXT
	) RETURNS VOID AS $$
	BEGIN
		DELETE FROM
			TMP.UserTokens
			WHERE
				UserID = AUserID
				AND Token = AToken;
	END;
	$$ LANGUAGE plpgsql VOLATILE;

	-- Checks that a token exists for a user and that it has not expired.
	CREATE OR REPLACE FUNCTION TMP.ValidateUser (
		AUserID		UUID,
		AToken		TEXT,
		---
		OUT OValid	BOOLEAN
	) RETURNS BOOLEAN AS $$
	BEGIN
		PERFORM 1
			FROM
				TMP.UserTokens
			WHERE
				UserID = AUserID
				AND Token = AToken
				AND Expires > NOW();

		OValid := FOUND;
	END;
	$$ LANGUAGE plpgsql STABLE;

	-- Creates a new 'identity' for a user. An identity is a person-friendly
	-- identifier for a particular user. Multiple identities per user are
	-- permitted, e.g. email, phone, social, etc.
	CREATE OR REPLACE FUNCTION TMP.AddUserIdentity (
		AUserID		UUID,
		ALoginType	TMP.LOGINTYPE,
		AIdentifier	TEXT,
		APassword	TEXT,
		--
		OUT OSuccessful	BOOLEAN
	) RETURNS BOOLEAN AS $$
	DECLARE
		VTableName	TEXT;
		VFound		BOOLEAN;
	BEGIN
		IF NOT EXISTS(
			SELECT 1
				FROM
					TMP.Users
				WHERE
					ObjectID = AUserID
		) THEN
			RAISE EXCEPTION 'user_not_found';
		END IF;
				
		INSERT INTO TMP.UserIdentities (
			UserID, LoginType, Identifier, Password, UserType
		) VALUES (
			AUserID, ALoginType, AIdentifier, APassword, AUserType
		);

		OSuccessful := FOUND;
	EXCEPTION
		WHEN unique_violation THEN
			RAISE EXCEPTION 'identity_already_exists %', AIdentifier;
	END;
	$$ LANGUAGE plpgsql VOLATILE;

	-- Adds a CRUD permission to a user and an object pair.
	CREATE OR REPLACE FUNCTION TMP.AddUserPermission (
		AUserID		UUID,
		AObjectID	UUID,
		APermission	TMP.PERMISSION,
		--
		OUT OSuccessful	BOOLEAN
	) RETURNS BOOLEAN AS $$
	BEGIN
		INSERT INTO TMP.UserPermissions (
			UserID, TargetObjectID, Permission
		) VALUES (
			AUserID, AObjectID, APermission
		);

		OSuccessful := FOUND;
	END;
	$$ LANGUAGE plpgsql VOLATILE;

	-- Removes a CRUD permission from a user and an object pair.
	CREATE OR REPLACE FUNCTION TMP.RemoveUserPermission (
		AUserID		UUID,
		AObjectID	UUID,
		APermission	TMP.PERMISSION,
		--
		OUT OSuccessful	BOOLEAN
	) RETURNS BOOLEAN AS $$
	BEGIN
		DELETE FROM TMP.UserPermission
			WHERE
				UserID = AUserID
				AND TargetObjectID = AObjectID
				AND Permission = APermission;

		OSuccessful := FOUND;
	END;
	$$ LANGUAGE plpgsql VOLATILE;

	-- Checks whether a user has any of the permissions in APermissions
	-- on the object.
	CREATE OR REPLACE FUNCTION TMP.HasPermission (
		AUserID		UUID,
		AObjectID	UUID,
		VARIADIC APermissions	TMP.PERMISSION[],
		--
		OUT OHasPermission	BOOLEAN
	) RETURNS BOOLEAN AS $$
	BEGIN
		-- ToDo: Perform recursively.
		PERFORM 1
			FROM
				TMP.UserPermissions
				WHERE
					UserID = AUserID
					AND TargetObjectID = AObjectID
					AND InArray(APermissions, Permission)
				LIMIT 1;

		OHasPermission := FOUND;
	END;
	$$ LANGUAGE plpgsql STABLE;
	
COMMIT;