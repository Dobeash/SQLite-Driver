REBOL [
	Title:		"SQLite driver"
	Owner:		"Ashley G Truter"
	Version:	2.1.1
	Date:		12-Aug-2012
	Purpose:	"REBOL front-end to SQLite"
	Usage: {

			SQLite functions
				check		Check DB integrity
				connect		Open a SQLite database
				describe	Information about a database object
				disconnect	Close database connection
				export		Export buffer to a CSV, HTML or TXT file
				import		Import CSV file into a table
				rows		Return row count
				sql			Prepare and execute an SQL statement
				tables		List all database objects

			CSV functions
				read-csv	Extracts values from a CSV file
				write-csv	Writes CSV values to a file

			Windows functions
				sqlcmd		Execute a SQL Server statement
				unzip		Extracts files from archive
				xls2csv		Convert an XLS file into CSV
	}
	Licence:	"MIT. Free for both commercial and non-commercial use."
]

SQLite: make object! [

	;	SQL Server
	server:			"gunter"
	database:		"AshleyDB"

	;	Directives
	format?:		true					; format output
	import?:		false					; pass SQL Server file to import

	;	Data structures
	buffer:			make block! 1024 * 64	; result buffer
	columns:		make block! 32			; column names of last select
	widths:			make block! 32			; column widths of last select

	;	State variables
	db-file:								; Database file (set by connect)
	dbid:									; Database ID
	sid:			none					; Statement ID
	transaction:	0						; nested transaction counter
	util-path:		system/script/path		; base path to sqlite3 (used by import and xls2csv.vbs)
	sqlite3-path:	%sqlite3				; path to sqlite3 admin

	;	Result codes
	SQLITE_OK:		0						; Successful result
	SQLITE_ROW:		100						; sqlite_step() has another row ready
	SQLITE_DONE:	101						; sqlite_step() has finished executing

	;	Reserved words

	keywords: ["ABORT" "ACTION" "ADD" "AFTER" "ALL" "ALTER" "ANALYZE" "AND" "AS" "ASC" "ATTACH" "AUTOINCREMENT" "BEFORE" "BEGIN" "BETWEEN" "BY" "CASCADE" "CASE" "CAST" "CHECK" "COLLATE" "COLUMN" "COMMIT" "CONFLICT" "CONSTRAINT" "CREATE" "CROSS" "CURRENT_DATE" "CURRENT_TIME" "CURRENT_TIMESTAMP" "DATABASE" "DEFAULT" "DEFERRABLE" "DEFERRED" "DELETE" "DESC" "DETACH" "DISTINCT" "DROP" "EACH" "ELSE" "END" "ESCAPE" "EXCEPT" "EXCLUSIVE" "EXISTS" "EXPLAIN" "FAIL" "FOR" "FOREIGN" "FROM" "FULL" "GLOB" "GROUP" "HAVING" "IF" "IGNORE" "IMMEDIATE" "IN" "INDEX" "INDEXED" "INITIALLY" "INNER" "INSERT" "INSTEAD" "INTERSECT" "INTO" "IS" "ISNULL" "JOIN" "KEY" "LEFT" "LIKE" "LIMIT" "MATCH" "NATURAL" "NO" "NOT" "NOTNULL" "NULL" "OF" "OFFSET" "ON" "OR" "ORDER" "OUTER" "PLAN" "PRAGMA" "PRIMARY" "QUERY" "RAISE" "REFERENCES" "REGEXP" "REINDEX" "RELEASE" "RENAME" "REPLACE" "RESTRICT" "RIGHT" "ROLLBACK" "ROW" "SAVEPOINT" "SELECT" "SET" "TABLE" "TEMP" "TEMPORARY" "THEN" "TO" "TRANSACTION" "TRIGGER" "UNION" "UNIQUE" "UPDATE" "USING" "VACUUM" "VALUES" "VIEW" "VIRTUAL" "WHEN" "WHERE"]

	;
	;	SQLite Library functions
	;

	*lib: load/library switch/default fourth system/version [
		2	[%/usr/lib/libsqlite3.dylib]
		3	[sqlite3-path: make string! reduce [{"} to-local-file join system/script/path %sqlite3 {"}] %sqlite3.dll]
	] [%libsqlite3.so]

	version: to tuple! do make routine! [return: [string!]] *lib "sqlite3_libversion"

	*bind-blob:			make routine! [stmt [integer!] idx [integer!] val [string!] len [integer!] fn [integer!] return: [integer!]] *lib "sqlite3_bind_blob"
	*bind-double:		make routine! [stmt [integer!] idx [integer!] val [decimal!] return: [integer!]] *lib "sqlite3_bind_double"
	*bind-int:			make routine! [stmt [integer!] idx [integer!] val [integer!] return: [integer!]] *lib "sqlite3_bind_int"
	*bind-null:			make routine! [stmt [integer!] idx [integer!] return: [integer!]] *lib "sqlite3_bind_null"
	*bind-text:			make routine! [stmt [integer!] idx [integer!] val [string!] len [integer!] fn [integer!] return: [integer!]] *lib "sqlite3_bind_text"
	*close:				make routine! [db [integer!] return: [integer!]] *lib "sqlite3_close"
	*column-blob:		make routine! [stmt [integer!] idx [integer!] return: [string!]] *lib "sqlite3_column_blob"
	*changes:			make routine! [db [integer!] return: [integer!]] *lib "sqlite3_changes"
	*column-count:		make routine! [stmt [integer!] return: [integer!]] *lib "sqlite3_column_count"
	*column-double:		make routine! [stmt [integer!] idx [integer!] return: [decimal!]] *lib "sqlite3_column_double"
	*column-integer:	make routine! [stmt [integer!] idx [integer!] return: [integer!]] *lib "sqlite3_column_int"
	*column-name:		make routine! [stmt [integer!] idx [integer!] return: [string!]] *lib "sqlite3_column_name"
	*column-text:		make routine! [stmt [integer!] idx [integer!] return: [string!]] *lib "sqlite3_column_text"
	*column-type:		make routine! [stmt [integer!] idx [integer!] return: [integer!]] *lib "sqlite3_column_type"
	*errmsg:			make routine! [db [integer!] return: [string!]] *lib "sqlite3_errmsg"
	*finalize:			make routine! [stmt [integer!] return: [integer!]] *lib "sqlite3_finalize"
	*open:				make routine! [name [string!] db-handle [struct! [[integer!]]] return: [integer!]] *lib "sqlite3_open"
	*prepare:			make routine! [db [integer!] dbq [string!] len [integer!] stmt [struct! [[integer!]]] dummy [struct! [[integer!]]] return: [integer!]] *lib "sqlite3_prepare_v2"
	*step:				make routine! [stmt [integer!] return: [integer!]] *lib "sqlite3_step"

	;	Helper functions
	;		connected?	Tests if connected
	;		db-object?	Tests if object exists
	;		enquote		Double quotes a string
	;		format		Used by SQL to format output
	;		sql-error	Used when an error occurs
	;		valid		Validates table and column names
	;		windows?	Test if on Windows

	connected?: make function! [] [
		any [dbid sql-error "DB: Not connected"]
	]

	db-object?: make function! [
		object [string! word!]
	] [
		not empty? sql/quiet reduce ["select 1 from sqlite_master where upper(name) = upper(?)" object]
	]

	enquote: make function! [
		value [series!]
	] [
		make string! reduce [{"} value {"}]
	]

	format: make function! [
		/local cols rows p offsets line width val
	] [
		all [empty? buffer exit]
		rows: (length? buffer) / cols: length? columns
		;	widths
		clear widths
		foreach column columns [
			insert tail widths length? form column
		]
		p: 1
		loop rows [
			repeat col cols [
				poke widths col max pick widths col length? form pick buffer ++ p
			]
		]
		;	offsets
		offsets: copy [1]
		foreach width widths [
			insert tail offsets width + 1 + last offsets
		]
		line: make string! 2 * width: -2 + last offsets
		;	headings
		insert/dup clear line " " width
		repeat i cols [
			insert at line pick offsets i pick columns i
		]
		print copy/part line width
		;	separators
		insert/dup clear line "-" width
		for i 2 cols 1 [
			poke line -1 + pick offsets i #" "
		]
		print line
		;	results
		p: 1
		loop rows [
			insert/dup clear line " " width
			repeat i cols [
				insert at line either any-string? val: pick buffer ++ p [pick offsets i] [(pick offsets i + 1) - 1 - length? form val] val
			]
			print copy/part line width
		]
	]

	sql-error: make function! [
		error [string! integer!]
		/local rc
	] [
		if integer? error [
			rc: error
			if "not an error" = error: *errmsg dbid [
				error: select [
					0	"OK: Successful result"
					1	"ERROR: SQL error or missing database"
					2	"INTERNAL: An internal logic error in SQLite"
					3	"PERM: Access permission denied"
					4	"ABORT: Callback routine requested an abort"
					5	"BUSY: The database file is locked"
					6	"LOCKED: A table in the database is locked"
					7	"NOMEM: A malloc() failed"
					8	"READONLY: Attempt to write a readonly database"
					9	"INTERRUPT: Operation terminated by sqlite_interrupt()"
					10	"IOERR: Some kind of disk I/O error occurred"
					11	"CORRUPT: The database disk image is malformed"
					12	"NOTFOUND: (Internal Only) Table or record not found"
					13	"FULL: Insertion failed because database is full"
					14	"CANTOPEN: Unable to open the database file"
					15	"PROTOCOL: Database lock protocol error"
					16	"EMPTY: (Internal Only) Database table is empty"
					17	"SCHEMA: The database schema changed"
					18	"TOOBIG: Too much data for one row of a table"
					19	"CONSTRAINT: Abort due to constraint violation"
					20	"MISMATCH: Data type mismatch"
					21	"MISUSE: Library used incorrectly"
					22	"NOLFS: Uses OS features not supported on host"
					23	"AUTH: Authorization denied"
					24	"FORMAT: Auxiliary database format error"
					25	"RANGE: 2nd parameter to sqlite3_bind out of range"
					26	"NOTADB: File opened that is not a database file"
					100	"ROW: sqlite_step() has another row ready"
					101	"DONE: sqlite_step() has finished executing"
				] rc
			]
		]
		make error! error
	]

	digit:		make bitset! [#"0" - #"9"]
	alpha:		make bitset! [#"A" - #"Z" #"a" - #"z" #"_"]
	alphanum:	union alpha digit

	valid: make function! [
		name [string! word!]
	] [
		if any [empty? name: trim form name not find alpha first name] [insert name "_"]
		remove-each char name [not find alphanum char]
		all [find keywords name insert tail insert name "[" "]"]
		name
	]

	windows?: make function [] [
		any [3 = fourth system/version sql-error "Cannot use on a non-Windows system"]
	]

	;	Database access functions

	set 'check make function! [
		"Check DB integrity."
	] [
		all ["ok" <> first sql/quiet "PRAGMA integrity_check" sql-error reform ["DB: Integrity check failed -" db-file]]
	]

	set 'connect make function! [
		"Open a SQLite database."
		database [file!]
		/local tmp rc
	] [
		all [dbid either %sqlite3.db = last split-path to-rebol-file db-file [disconnect delete to-rebol-file db-file] [sql-error "DB: Already connected"]]
		all [#"/" <> first database insert database: copy database system/script/path]
		all [SQLITE_OK <> rc: *open db-file: form to-local-file database tmp: make struct! [p [integer!]] none sql-error rc]
		dbid: tmp/p
		either format? [print ["Connected" dbid]] [dbid]
	]

	set 'describe make function! [
		"Information about a database object."
		object [string! word!]
		/local buf
	] [
		connected?
		any [db-object? object exit]
		either "index" = first sql/quiet reduce ["select type from sqlite_master where name like ?" object] [
			sql make string! reduce ["PRAGMA index_info (" object ")"]						; seqno,cid,name
		] [
			buf: copy sql/quiet make string! reduce ["PRAGMA table_info (" object ")"]	; cid,name,type,notnull,dflt_value,pk
			sql/quiet make string! reduce ["PRAGMA index_list (" object ")"]
			unless empty? buffer [
				all [
					format?
					insert buffer reduce ["" "" "" "SEQ" "NAME" "UNIQUE" "^/" "^/" "^/"]
				]
				foreach [c1 c2 c3] buffer [
					insert tail buf reduce [c1 c2 c3 "" "" ""]
				]
			]
			sql/quiet make string! reduce ["PRAGMA foreign_key_list (" object ")"]
			unless empty? buffer [
				all [
					format?
					insert tail buf reduce ["" "" "" "" "" "" "TABLE" "FROM" "TO" "ON_UPDATE" "ON_DELETE" "MATCH" "^/" "^/" "^/" "^/" "^/" "^/"]
				]
				foreach [c1 c2 c3 c4 c5 c6 c7 c8] buffer [
					insert tail buf reduce [c3 c4 c5 c6 c7 c8]
				]
			]
			insert clear buffer buf
			either format? [
				insert clear columns ["CID" "NAME" "TYPE" "NOTNULL" "DFLT_VALUE" "PK"]
				while [buf: find buffer "^/"] [
					insert/dup clear first buf "=" 9
				]
				format
			] [buffer]
		]
	]

	set 'disconnect make function! [
		"Close database connection."
		/local rc
	] [
		any [dbid exit]
		all [SQLITE_OK <> rc: *close dbid sql-error rc]
		dbid: none
	]

	set 'export make function! [
		"Export buffer to a CSV file."
		file [file!]
		statement [string! block!] "SQL statement"
		/header "Include column header"
		/tab "Tab delimited"
		/sqlserver
	] [
		either sqlserver [sqlcmd statement] [connected? sql/quiet statement]
		either empty? buffer [print "No rows exported"] [
			all [header insert buffer columns]
			write-csv/delimit file length? columns buffer either tab [#"^-"] [#","]
			print ["Exported" divide length? buffer length? columns "rows to" file]
		]
	]

	set 'import make function! [
		"Import block into a table."
		table [string! word!]
		data [block!]
		/header names [block!] "Column names"
		/key keys [block!] "Primary key column numbers"
		/local cols s val file row
	] [
		all [empty? data exit]
		connected?
		;	----------------------------------------------------------------------------------------------------
		all [header insert clear columns names]
		cols: length? columns
		any [import? zero? mod length? data cols make error! "block length must be a multiple of columns"]
		while [cols <> length? unique columns] [
			repeat i cols [
				if s: find skip columns i pick columns i [
					repeat j cols [
						unless find columns join first s j + 1 [
							insert tail first s j + 1
							break
						]
					]
				]
			]
		]
		;	----------------------------------------------------------------------------------------------------
		s: reform ["create table if not exists" table: valid table "("]
		either import? [
			row: parse/all join first data " " "^-"
			trim last row
		] [
			row: copy/part data cols
		]
		repeat i cols [
			insert tail s reform [
				pick columns i
				case [
					integer? val: pick row i				["INTEGER"]
					decimal? val							["REAL"]
					any [not string? val empty? val]		["TEXT collate nocase"]
					empty? trim/with copy val "-0123456789"	[either attempt [to integer! val] ["INTEGER"] ["TEXT collate nocase"]]
					empty? trim/with copy val ".-0123456789"[either attempt [to decimal! val] ["REAL"] ["TEXT collate nocase"]]
					true									["TEXT collate nocase"]
				]
				","
			]
		]
		if key [
			insert tail s "PRIMARY KEY ("
			foreach i keys [
				insert tail s reform [pick columns i ","]
			]
			insert back tail s ")"
		]
		poke s length? s #")"
		sql/quiet s
		;	----------------------------------------------------------------------------------------------------
		file: %sqlite.dat
		print either import? [
			write/lines file data
			import?: false
			[length? data "rows imported"]
		][
			write-csv/delimit file cols data #"^-"
			[divide length? data cols "rows imported"]
		]
		either zero? call/wait/error reform ["(echo .mode tabs && echo .import" file table ")|" sqlite3-path enquote db-file] s [
			delete file
		] [sql-error reform ["IMPORT" table trim/lines s]]
	]
	
	set 'rows make function! [
		"Return row count."
		table [string! word!]
	] [
		connected?
		any [db-object? table exit]
		sql/quiet reform ["select count(*) from" table]
		either format? [print first buffer] [first buffer]
	]

	set 'sql make function! [
		"Prepare and execute an SQL statement."
		statement [string! block!] "SQL statement"
		/quiet "Ignore format directive"
		/local stmt val cols rc idx
	] [
		connected?
		;	prepare statement
		stmt: trim either string? statement [statement] [first statement]
		;	check if this is a nested transaction statement
		switch stmt [
			"begin"		[all [1 <= ++ transaction exit]]
			"commit"	[all [1 < -- transaction exit]]
			"end"		[all [1 < -- transaction exit]]
			"rollback"	[transaction: 0]
		]
		all [find ["begin" "commit" "end" "rollback" "analyze" "vacuum"] stmt quiet: true]
		;	refinements
		unless SQLITE_OK = rc: *prepare dbid stmt length? stmt sid: make struct! [p [integer!]] none make struct! [[integer!]] none [sql-error rc]
		sid: sid/p
		;	bind ?
		if block? statement [
			remove statement
			repeat i length? statement [
				if SQLITE_OK <> rc: switch/default type?/word val: pick statement i [
					integer!	[*bind-int sid i val]
					decimal!	[*bind-double sid i val]
					binary!		[*bind-blob sid i val: enbase val length? val 0]
					none!		[*bind-null sid i]
				] [
					*bind-text sid i val: form val length? val 0
				] [*finalize sid sql-error rc]
			]
		]
		;	return unless rows await
		either find ["SE" "PR" "EX"] copy/part stmt 2 [
			clear buffer
			;	obtain column count and names
			clear columns
			repeat i cols: *column-count sid [
				insert tail columns *column-name sid i - 1
			]
			;	retrieve values
			do compose/deep [
				while [(SQLITE_ROW) = rc: *step (sid)] [
					idx: 0
					repeat i (cols) [
						insert tail buffer do pick [
							[*column-integer (sid) idx]		; SQLITE_INTEGER
							[*column-double (sid) idx]		; SQLITE_REAL
							[*column-text (sid) idx]		; SQLITE_TEXT
							[debase *column-blob (sid) idx]	; SQLITE_BLOB
							[none]							; SQLITE_NULL
						] *column-type (sid) idx
						idx: i
					]
				]
			]
			*finalize sid
			all [SQLITE_DONE <> rc sql-error rc]
			either all [not quiet format?] [format] [buffer]
		] [
			rc: *step sid
			*finalize sid
			all [SQLITE_DONE <> rc sql-error rc]
			either all [not quiet find ["DE" "UP" "IN"] copy/part stmt 2] [print [*changes dbid "rows affected"]] [exit]
		]
	]

	set 'tables make function! [
		"List all database objects."
		/pagesize "List DB page size"
		/database "List attached database files"
		/indexes "List indexes"
		/views "List views"
		/local blk
	] [
		connected?
		switch/default true reduce [
			pagesize	[sql "PRAGMA page_size"]
			database 	[sql "PRAGMA database_list"]
			indexes		[sql "select name,tbl_name as 'TABLE' from sqlite_master where type = 'index' order by 1"]
			views		[sql "select name,tbl_name as 'TABLE' from sqlite_master where type = 'view' order by 1"]
		][
			blk: copy sql/quiet "select name,type from sqlite_master where type = 'table' order by 1"
			repeat i length? blk [
				all [odd? i poke blk i + 1 first sql/quiet reform ["select count(*) from" pick blk i]]
			]
			insert clear columns ["TABLE" "ROWS"]
			insert clear buffer blk
			either format? [format] [buffer]
		]
	]

	;
	;	CSV functions
	;

	set 'read-csv make function! [
		"Extracts values from a CSV file."
		file [file! url!]
		/skip "Skips a number of lines"
			lines [integer!]
		/header "First line after skip is header"
		/part "Reads specified columns"
			positions [block!] "Block of integer! column positions"
		/exclude "Excludes rows meeting rule"
			rule [block!] "Can reference 'row as a string!"
		/transform "Alter contents of row"
			statement [block!] "Can reference 'row as a block! post any exclude rule"
		/delimit "Specify an alternate delimiter (default is tab then comma)"
			delimiter [char!]
		/local cols buf xls? indent?
	] [
		xls?: either find [%.xls %.xlsx] suffix? file [
			all [empty? file: xls2csv file make error! "spreadsheet contains no data"]
			file: first file
		] [none]
		buf: last read/direct/lines/part file 1 + any [lines 0]
		any [delimit delimiter: either find buf #"^-" [#"^-"] [#","]]
		indent?: either all [xls? delimiter = first buf] [remove buf true] [false]
		cols: length? buf: parse/all join buf " " form delimiter
		either part [
			foreach i positions [unless all [integer? i i > 0 i <= cols] [make error! reform [i "not a valid position"]]]
		][
			positions: copy []
			repeat i cols [insert tail positions i]
		]
		clear buffer
		file: open/direct/read/lines file
		all [skip copy/part file lines]
		all [header header: buf copy/part file 1]
		do compose/deep [
			while [buf: copy/part file 10000] [
				foreach row (either exclude [[remove-each row]][]) buf (either exclude [compose/deep [[(rule)]]][]) [
					(
						either indent? [[remove row]] []
					)
					(
						either find positions cols [compose/deep [all [(delimiter) = last row insert tail row (delimiter)]]] []
					)
					unless empty? trim form row: parse/all row (form delimiter) [
						(
							either transform [compose [(statement)]] []
						)
						foreach i [(positions)] [insert tail buffer trim/lines pick row i]
					]
				]
			]
		]
		close file
		file: buf: none
		recycle
		all [xls? delete xls?]
		clear columns
		either header [
			foreach i positions [insert tail columns valid pick header i]
		][
			repeat i length? positions [insert tail columns either i < 27 [form #"@" + i] [join "A" #"&" + i]]
		]
		copy buffer
	]

	set 'write-csv make function! [
		"Writes CSV values to a file."
		file [file! url!]
		width [integer!] "Number of columns"
		block [block!] "Block of values to write"
		/delimit "Specify an alternate delimiter (default is comma)"
			delimiter [char!]
		/append "Writes to the end of an existing file"
		/local string idx val
	] [
		all [empty? block exit]
		any [positive? width make error! "width must be a positive number"]
		any [zero? mod length? block width make error! "block length must be a multiple of width"]
		any [delimiter delimiter: #","]
		string: make string! 1000000
		idx: 1
		do compose/deep [
			loop (divide length? block width) [
				repeat col (width) [
					insert insert tail string either all [series? val: pick block ++ idx find val (form delimiter)] [enquote val] [val] (form delimiter)
				]
				poke string length? string #"^/"
			]
		]
		either append [write/append file string] [write file string]
		string: none
		recycle
	]

	;
	;	Windows functions
	;

	set 'sqlcmd make function! [
		"Execute a SQL Server statement."
		statement [string!]
		/direct
		/local data
	][
		windows?
		call/wait reform ["sqlcmd -S" server "-d" database "-Q" enquote trim/lines statement {-o sqlcmd.txt -W -w 4096 -s"	"}]
		data: read/lines %sqlcmd.txt
		delete %sqlcmd.txt
		all [empty? data exit]
		all [2 = length? data print last data exit]
		clear columns
		foreach column parse/all first data "^-" [
			insert tail columns valid column
		]
		remove/part data 2
		clear at tail data -2
		either direct [
			import?: true
			data
		] [
			clear buffer
			foreach line data [
				all [#"^-" = last line insert tail line "^-"]
				replace/all line {"} {'}
				insert tail buffer parse/all line "^-"
			]
			any [zero? mod length? buffer length? columns sql-error "block length must be a multiple of width"]
			buffer
		]
	]

	set 'unzip make function! [
		"Extracts files from archive."
		file [file!]
		/local path files
	] [
		windows?
		any [exists? file exit]
		files: read path: first split-path file
		call/wait reform [enquote "C:\Program Files\7-Zip\7z.exe" "e" enquote to-local-file file "-y" join "-o" enquote to-local-file path]
		print ["! extracted" length? files: difference files read path "files from" file]
		files
	]

	set 'xls2csv make function! [
		"Convert an XLS file into CSV."
		file [file!]
		/local path files s
	] [
		windows?
		any [exists? file exit]
		unless zero? call/wait reform [to-local-file join util-path %xls2csv.vbs enquote to-local-file join system/script/path file] [
			print ["XLS2CSV: Failed to convert -" file]
		]
		s: replace last split-path file suffix? file ""
		files: copy []
		foreach sheet remove-each f read path: first split-path file [
			any [
				%.csv <> suffix? f
				s <> copy/part f length? s
			]
		] [
			either 2 = size? join path sheet [delete join path sheet] [insert tail files sheet]
		]
		files
	]
]

attempt [delete %sqlite3.db]
connect %sqlite3.db