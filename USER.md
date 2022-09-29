# User Guide

## SQL

The following SQL statements and expressions are supported by the SQLite3 library.

Type              | Statements
----------------- | ----------
Connections       | [ATTACH](http://www.sqlite.org/lang_attach.html)<br>[DETACH](http://www.sqlite.org/lang_detach.html)
[Transactions](http://www.sqlite.org/lang_transaction.html)|BEGIN<br>COMMIT<br>ROLLBACK
Data Definition   | [ALTER](http://www.sqlite.org/lang_altertable.html)<br>CREATE [INDEX](http://www.sqlite.org/lang_createindex.html) [TABLE](http://www.sqlite.org/lang_createtable.html) [TRIGGER](http://www.sqlite.org/lang_createtrigger.html) [VIEW](http://www.sqlite.org/lang_createview.html)<br>DROP [INDEX](http://www.sqlite.org/lang_dropindex.html) [TABLE](http://www.sqlite.org/lang_droptable.html) [TRIGGER](http://www.sqlite.org/lang_droptrigger.html) [VIEW](http://www.sqlite.org/lang_dropview.html)
Data Maintenance  | [ANALYZE](http://www.sqlite.org/lang_analyze.html)<br>[REINDEX](http://www.sqlite.org/lang_reindex.html)<br>[VACUUM](http://www.sqlite.org/lang_vacuum.html)
Data Manipulation | [DELETE](http://www.sqlite.org/lang_delete.html)<br>[EXPLAIN](http://www.sqlite.org/lang_explain.html)<br>[INSERT](http://www.sqlite.org/lang_insert.html)<br>[SELECT](http://www.sqlite.org/lang_select.html)<br>[UPDATE](http://www.sqlite.org/lang_update.html)<br>[expressions](http://www.sqlite.org/lang_expr.html)

## Database access functions

Eleven database access functions are used to open, access and close SQLite database files.

### CONNECT

	USAGE:
		CONNECT database /create /flat /direct /timeout retries /format /info /log

	DESCRIPTION:
		Open a SQLite database.

	ARGUMENTS:
		database -- (Type: file block)

	REFINEMENTS:
		/create -- Create database if non-existant
		/flat -- Do not return rows as blocks
		/direct -- Do not mold/load Rebol values
		/timeout -- Specify alternate retry limit (default is 5)
			retries -- Number of 1 second interval retries if SQLITE_BUSY (Type: integer)
		/format -- Format output
		/info -- Obtain column names and widths
		/log -- Log all SQL statements

If `database` is provided as a block of files then the first file specified will be opened and the remaining files (up to a limit of ten) [attached](http://www.sqlite.org/lang_attach.html) to it. Tables that are unique across all attached databases do not need to be qualified (with the database name) when referenced within SQL statements.

#### Create

The `CONNECT` function is used to open a SQLite database file. An error will occur if this file does not exist, but using the `/create` refinement will create the database file if it does not already exist.

#### Flat

This refinement controls how values are returned from a `SELECT` statement; either with each row in its own block (the default) or all values in a single block. As an example, assume we have a table with two columns and two rows.

	>> connect %test.db
	>> sql "select * from t"
	== [["A" 1] ["B" 2]]

and:

	>> connect/flat %test.db
	>> sql "select * from t"
	== ["A" 1 "B" 2]

Although the first form is often easier to work with, the second is much more efficient; especially when large numbers of rows are returned.

#### Direct

By default, the driver will `mold` non-numeric values that are inserted into tables and `load` them when selected. This ensures values like:

	"A string"
	a-word
	1-Jan-2006

are stored as SQLite TEXT in the form:

	{"A string"}
	{a-word}
	{1-Jan-2006}

which `load` subsequently returns to their original Rebol datatype(s).

Apart from the conversion overhead, there is an obvious two byte storage overhead with each and every `string!` value. If your database only needs to store and access numerical data and strings (i.e. you are not interested in other Rebol datatypes) then using the `/direct` refinement will bypass this conversion and save storage space.

#### Timeout

When a SQL statement receives a `SQLITE_BUSY` return code, because another process has a file lock, the statement will be retried up to five times (by default) at one second intervals. This refinement enables you to specify an alternate retry limit that better suits your operating environment.

#### Format

This causes all output to be printed to the console in a MySQL-like format.

Note that as the width of each value must be individually determined it is not recommended that you use this refinement with large result sets (like any other console output it can always be stopped by pressing ESC).

#### Info

Every SQL statement will have its columns stored in `SQLite/columns` and its column widths stored in `SQLite/widths`. This refinement is for those who wish to create their own SQL display clients and carries similar performance penalties as covered in the #format# refinement above.

#### Log

Every connect, disconnect, error, SQL statement and statement retry will be logged to `%sqlite.log`. While this can be useful to monitor what SQL statements are being issued and what the volume and distribution is; be sure to monitor the size of this file in high transaction environments.

### DATABASE

	USAGE:
		DATABASE /analyze /vacuum /check

	DESCRIPTION:
		Database tasks.

	REFINEMENTS:
		/analyze -- Gather statistics on indexes
		/vacuum -- Reclaim unused space
		/check -- Perform an integrity check

#### analyze

Gathers and stores statistics about tables and indices so the query optimizer can use them to help make better query planning choices. See http://www.sqlite.org/lang_analyze.html for more details.

#### vacuum

Rebuilds the entire database. See http://www.sqlite.org/lang_vacuum.html for more details.

#### check

Performs an inegrity check looking for out-of-order records, missing pages, malformed records, and corrupt indices. See http://www.sqlite.org/pragma.html#pragma_integrity_check for more details.

### DESCRIBE

	USAGE:
		DESCRIBE object /index /indexes /fkeys

	DESCRIPTION:
		Information about a database object (default is table).

	ARGUMENTS:
		object -- (Type: string)

	REFINEMENTS:
		/index -- Describes an index
		/indexes -- Indexes on table
		/fkeys -- Foreign keys that reference table

By default this function returns a flat block (see the `/flat` refinement of `CONNECT`) consisting of the following six values per column, in ascending column number order.

Column     | Type    | Description
---------- | ------- | ----------------
cid        | integer | Column ID
name       | string  | Column name
type       | string  | Column type
notnull    | integer | Not null flag
dflt_value | any     | Default value
pk         | integer | Primary key flag

#### Index

This refinement instead returns information about a specific index.

Column     | Type    | Description
---------- | ------- | ----------------
seqno      | integer | Sequence number
cid        | integer | Column ID
name       | string  | Column name

#### Indexes

This refinement returns information about the indexes on a table.

Column     | Type    | Description
---------- | ------- | ----------------
seq        | integer | Sequence
name       | string  | Index name
unique     | integer | Unique flag

#### Fkeys

This refinement returns information about the foreign keys (if any) that reference a table.

Column     | Type    | Description
---------- | ------- | ----------------
id         | integer | The index of the foreign key in the list of foreign keys for the table - 0-based
seq        | integer | The index of the column referenced in the foreign key - 0-based
table      | string  | The name of the referenced table
from       | string  | The column name in the local table
to         | string  | The column name in the referenced table

### DISCONNECT

	USAGE:
		DISCONNECT

	DESCRIPTION:
		Close database connection.

This function closes the current database file using the /Database Identifier/ stored in `SQLite/dbid`.

### EXPLAIN

	USAGE:
		EXPLAIN statement

	DESCRIPTION:
		Explain an SQL statement.
		EXPLAIN is a function value.

	ARGUMENTS:
		statement -- SQL statement (Type: string block)

### EXPORT

	USAGE:
		EXPORT file statement

	DESCRIPTION:
		Export result table to a CSV file.
		EXPORT is a function value.

	ARGUMENTS:
		file -- CSV file to export to (Type: file)
		statement -- SQL statement (Type: string block)

This function exports the result table to the specified file.

### IMPORT

	USAGE:
		IMPORT file /no-header

	DESCRIPTION:
		Import CSV file into a table.
		IMPORT is a function value.

	ARGUMENTS:
		file -- CSV file to import from (Type: file)

	REFINEMENTS:
		/no-header -- Use generic column names

This function imports a CSV file into a table with the same name as the file (less extension and spaces replaced with underscores).

### INDEXES

	USAGE:
		INDEXES

	DESCRIPTION:
		List all indexes.

This function returns three values for each index.

Column     | Type    | Description
---------- | ------- | ----------------
tbl_name   | string  | Table name
name       | string  | Index name
sql        | string  | Create syntax

### ROWS

	USAGE:
		ROWS table

	DESCRIPTION:
		Return row count.

	ARGUMENTS:
		table -- (Type: string)

### SQL

	USAGE:
		SQL statement /direct

	DESCRIPTION:
		Prepare and execute an SQL statement.

	ARGUMENTS:
		statement -- SQL statement (Type: string block)

	REFINEMENTS:
		/direct -- Do not mold/load Rebol values

This function lets you issue SQL statements such as [SELECT](http://www.sqlite.org/lang_select.html), [INSERT](http://www.sqlite.org/lang_insert.html), [UPDATE](http://www.sqlite.org/lang_update.html) and [DELETE](http://www.sqlite.org/lang_delete.html) against a SQLite database. See the *Driver Guide* for information on value binding and retrieval.

#### Flat

This refinement forces the current statement to be processed as if the `/flat` directive were in effect.

#### Direct

This refinement forces the current statement to be processed as if the `/direct` directive were in effect.

### TABLES

	USAGE:
		TABLES

	DESCRIPTION:
		List all tables.

This function returns two values for each table.

Column     | Type   | Description
---------- | ------ | -----------------
tbl_name   | string | Table name
sql        | string | SQL create syntax
