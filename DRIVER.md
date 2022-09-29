# Driver Guide

## The SQLite Driver object

The driver is implemented as a context named SQLite with nine functions exported to the global context. By convention, and to distinguish these *database* words from other words, the function names always appear in upper-case.

### Result codes

Of the twenty nine SQLite result codes defined [here](http://www.sqlite.org/capi3ref.html#SQLITE_ABORT), only four are used by the driver.

Code        | Meaning
----------- | -----------------------------------
SQLITE_OK   | Successful result.                 
SQLITE_BUSY | The database file is locked.       
SQLITE_ROW  | sqlite_step has another row ready. 
SQLITE_DONE | sqlite_step has finished executing.

### Library functions

Nineteen [SQLite library functions](http://www.sqlite.org/capi3ref.html) are implemented via matching `routine!` names, except that the `sqlite3_ prefix` is replaced with an aster and underscores are replaced with hyphens. All these routines, apart from `*open` and `*close`, are used in the `SQL` function.

Rebol Routine  | C/C++ API            
-------------- | ---------------------
bind-blob      | sqlite3_bind_blob    
bind-double    | sqlite3_bind_double  
bind-int       | sqlite3_bind_int     
bind-null      | sqlite3_bind_null    
bind-text      | sqlite3_bind_text    
close          | sqlite3_close        
column-blob    | sqlite3_column_blob  
column-count   | sqlite3_column_count 
column-double  | sqlite3_column_double
column-integer | sqlite3_column_int   
column-name    | sqlite3_column_name  
column-text    | sqlite3_column_text  
column-type    | sqlite3_column_type  
errmsg         | sqlite3_errmsg       
finalize       | sqlite3_finalize     
open           | sqlite3_open         
prepare        | sqlite3_prepare      
reset          | sqlite3_reset        
step           | sqlite3_step         

### Database access functions

The nine database access functions are exported to the global context and use the routines described above to open, access and close SQLite database files.

Function   | Description                          | Refinement(s)
---------- | ------------------------------------ | -------------
CONNECT    | Open a SQLite database               | `create` - Create database if non-existent<br>`flat` - Do not return rows as blocks<br>`direct` - Do not mold/load Rebol values<br>`timeout` - Specify alternate retry limit (default is 5)<br>`format` - Format output<br>`info` - Obtain column names and widths<br>`log` - Log all SQL statements
DATABASE   | Database tasks                       | `analyze` - Gather statistics on indexes<br>`vacuum` - Reclaim unused space<br>`check` - Perform an integrity check
DESCRIBE   | Information about a database object  | `index` - Describes an index<br>`indexes` - Indexes on table<br>`fkeys` - Foreign keys that reference table
DISCONNECT | Close database connection            | NA
EXPLAIN    | Explain an SQL statement             | NA
EXPORT     | Export result table to a CSV file    | NA
IMPORT     | Import CSV file into a table         | `no-header` - Use generic column names
INDEXES    | List all indexes                     | NA
ROWS       | Return row count                     | NA
SQL        | Prepare and execute an SQL statement | `direct` - Do not mold/load Rebol values
TABLES     | List all tables                      | NA

### Directives

Six directives, all of them set via CONNECT refinements, control various aspects of the driver's behaviour.

Directive   | Description                                       
----------- | --------------------------------------------------
`retry`     | Number of 1 second intervals to try if SQLITE_BUSY
`flat?`     | Don't return rows as blocks                       
`direct?`   | Bypass `mold/load` conversions                    
`log?`      | SQL statement logging                             
`format?`   | Format output                                     
`col-info?` | column names and widths                           

While it's rare that you need to change directives from the console, it can be quite useful when debugging to toggle the `format?` directive as follows:

	>> SQLite/format?: true
	>> SQL "select * from my-table"
	>> SQLite/format?: false

## Using the Driver

### SQL Statements

The SQL function supports statements in one of two forms:

- The entire statement as a single string, or
- A block with the first value being the statement string and subsequent values being the bind variables.

Examples of some string statements are:

	CONNECT/create %test.db
	SQL "create table t (col_1, col_2, col_3)"
	SQL {insert into t values (1, '1-Jan-2000', '"A string"')}
	SQL "select * from t where col_1 = 1"
	SQL "select * from t where col_2 = '1-Jan-2000'"
	SQL {select * from t where col_3 = '"A string"'}

If the database was opened with `CONNECT/direct` then the last statement would be written as:

	SQL "select * from t where col_3 = 'A string'"

### Value Binding

The SQLite driver supports value binding which makes it much easier to generate dynamic SQL statements within your code. Value binding works by replacing each unquoted `?` within your statement with the next value in the statement block. Using value binding, the examples above would be written as:

	SQL ["insert into t values (?, ?, ?)" 1 1-Jan-2000 "A string"]
	SQL ["select * from t where col_1 = ?" 1]
	SQL ["select * from t where col_2 = ?" 1-Jan-2000]
	SQL ["select * from t where col_3 = ?" "A string"]

As can be seen from these examples, value binding implicitly quotes Rebol values so you don't have to construct cumbersome statement strings yourself!

### Column Names

Sometimes you may need to know the column names (and widths) used in the last SELECT statement. These are available in the `SQLite/columns` block and can be used as follows:

	>> SQLite/col-info?: true
	== true
	>> SQL "select * from t"
	== []
	>> SQLite/columns
	== ["c1" "c2" "c3"]
	>> SQL "select count(*) from t"
	== [[0]]
	>> SQLite/columns
	== ["count(*)"]
	>> SQLite/col-info?: false
	== false

### SQL Buffer

SQL statements return their result set in a 32Kb value buffer which is returned as a reference. If you need to preserve a copy of these values, because another SQL statement will be executed, then make sure you copy the result set; as in:

	data: copy SQL "select * from t"

Unlike most Rebol functions, which return a copy of their result set, the SQLite driver returns a reference for several good reasons:

- A large buffer is allocated once at context creation.
- Copying a result set doubles the amount of memory used.
- It's trivial to make this reference a copy in your code, however the reverse is not true.
- Inline SQL statements (and many others) don't require a copy (this is especially true in the case of foreach constructs that iterate over the result set with no further SQL statements.)

### Transactions

SQLite is auto-commit by default which means that the changes caused by each statement are written out at the conclusion of the statement. This is good for concurrency (lock duration is minimized) but not so good when you need a set of statements to succeed or fail together (i.e. a logical "transaction"), or you have an INSERT in a tight loop. Consider the following:

	repeat i 1000 [
		SQL reduce [
			"insert into t values (?, ?, ?)" i now/date + i join "String " i
		]
	]

Not only will this take a long time, but it will cause significant disk thrashing.

Fortunately, SQLite lets you turn auto-commit off and on with the begin and commit statements. Doing the following:

	SQL "begin"
	repeat i 1000 [
		SQL reduce [
			"insert into t values (?, ?, ?)" i now/date + i join "String " i
		]
	]
	SQL "commit"

will dramatically improve the speed of this operation.

> Don't forget to commit as the database file will be locked until auto-commit is turned back on.