
******************************************************************
*                                                                *
*   CustomLineNumbers plugin v1.1.10 for Notepad++               *
*   Builds for 32 and 64 bits Notepad++ installations available  *
*                                                                *
*   Author: Andreas Heim, 2018 - 2024                            *
*                                                                *
******************************************************************



============
  Features
============

With this plugin you can display line numbers in the line numbers
margin of Notepad++ as hex numbers or as relative line numbers.
You can also configure the starting line number. Line numbers
displayed in the status bar are affected by these settings, too.
Hex display of column numbers follows line numbers setting, the
starting column number can be configured separately.


=================
  Installation
=================

1. If you run a 32 bits version of Notepad++ copy the file
   "bin\x86\CustomLineNumbers.dll" to the directory
   "plugins\CustomLineNumbers" of your Notepad++ installation.
   In case of a 64 bits version take the file
   "bin\x64\CustomLineNumbers.dll". You can find the "plugins"
   directory under the installation path of Notepad++. The
   directory "CustomLineNumbers" you have to create by yourself.

2. Copy the file "doc\CustomLineNumbers.txt" to the directory
   "plugins\CustomLineNumbers\doc". If it doesn't exist create it.



===========
  History
===========

v1.1.10 - May 2024
~~~~~~~~~~~~~~~~~~
- enhanced: Added new feature: offset for column numbers
- enhanced: Added new feature: column numbers as hex
- enhanced: Added new Scintilla constants up to v5.5.0


v1.1.9 - April 2024
~~~~~~~~~~~~~~~~~~~
- enhanced: Added new feature: relative line numbers
- enhanced: Improved documentation for Notepad++ messages
- enhanced: Added new Notepad++ message constants up to v8.6.5
- enhanced: Added new Notepad++ menu command ids up to v8.6.5
- enhanced: Added new Scintilla constants up to v5.4.3


v1.1.8 - November 2022
~~~~~~~~~~~~~~~~~~~~~~
- fixed:    When plugin's dialog boxes are on screen but hidden by
            another application's window which has input focus, it
            is not possible to return to Notepad++ by clicking its
            taskbar icon.
- fixed:    Wrong implementation of Notepad++ version comparison.
- enhanced: Added new Notepad++ message constants from v7.9.2 up
            to v8.4.7
- enhanced: Added new Notepad++ menu command ids from v7.9.6 up
            to 8.4.7
- enhanced: Added new Scintilla constants from v4.4.6 up to v5.3.1
- enhanced: Adapted to new Scintilla v5.3.1 API of Notepad++ v8.4.7


v1.1.7 - June 2019
~~~~~~~~~~~~~~~~~~
- changed: Adapted to new Scintilla API v4.1.4 in Notepad++ v7.7


v1.1.6 - November 2018
~~~~~~~~~~~~~~~~~~~~~~
- changed: Adopted new plugin hosting model of Notepad++ version
           v7.5.9 and higher.


v1.1.5 - October 2018
~~~~~~~~~~~~~~~~~~~~~
- fixed: Still problems with missing line numbers when changing
         height of Notepad++ window.


v1.1.4 - October 2018
~~~~~~~~~~~~~~~~~~~~~
- fixed: Missing line numbers when increasing height of Notepad++
         window.


v1.1.3 - October 2018
~~~~~~~~~~~~~~~~~~~~~
- fixed:   Severe performance decrease when editing files with even
           a few hundred lines.
- changed: Cursor feedback while line numbering removed.


v1.1.2 - October 2018
~~~~~~~~~~~~~~~~~~~~~
- fixed:    Notepad++ hangs for a while when it shuts down.
- enhanced: The plugin provides cursor feedback while line numbering.


v1.1.1 - October 2018
~~~~~~~~~~~~~~~~~~~~~
- fixed: Line numbers disappear after reloading a file.


v1.1 - October 2018
~~~~~~~~~~~~~~~~~~~
- enhanced: Displaying line numbers as hexadecimal numbers and line
  numbers offset can be configured now.
- enhanced: Reduced superfluous calls to line numbering function,
  useful especially when working with large files.


v1.0 - September 2018
~~~~~~~~~~~~~~~~~~~~~
- Initial version

