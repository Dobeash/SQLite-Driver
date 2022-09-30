# SQLite Driver

**This driver only works with Rebol2.**

![alt SQLite logo](http://sqlite.org/images/sqlite370_banner.gif)

> A self-contained, embeddable, zero-configuration SQL database engine.

The Rebol SQLite database driver uses the library access features of Rebol to provide native Rebol access to SQLite databases.

## What is SQLite?

For detailed information on SQLite, visit their [home page](http://www.sqlite.org). What's attractive from a Rebol perspective is:

 - **Cross platform** - It is written entirely in C, with precompiled binaries available for Windows, Linux and Mac OS X.
 - **One library** - The *database engine* is a single, small, drop-in file (`DLL` on Windows, `.so` for others) requiring no special installation or configuration.
 - **Public Domain** - The source and binaries are freely available for both commercial and non-commercial use with no restrictions whatsoever.
 - **Works well with Rebol** - It's simple and efficient design make it a natural fit for Rebol file-based database storage and access.
 - **Fast and powerful** - It provides a fast, full-featured, multi-user RDBMS solution that "works out of the box".

## Features

The SQLite driver provides a simplified wrapper to the SQLite library. Its features include:

 - **Works out of the box** - Just add `do %sqlite.r` to your script and you're ready to go.
 - **Native Rebol storage** - Your data is stored and accessed as Rebol values which means that you have the full range of Rebol data-types at your fingertips!
 - **Plays well** - The half-dozen functions that drive the database behave like any other Rebol function, accepting and returning Rebol values as you would expect.
 - **Lock detection** - The driver detects locks and initiates retries on your behalf.
 - **Configurable** - Many aspects of the driver's behaviour can be changed/controlled by specifying various refinements when you "connect" to a SQLite database.

## Documentation

> 20-Aug-2012

 - **DRIVER.md** - describes the design and operation of the SQLite Driver.
 - **USER.md** - describes the use of SQL & the DB access functions.
