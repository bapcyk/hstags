PowerShell Script to query and manipulate Haskell Tags
======================================================

Install
-------

Make script to be automatically loaded. For example, see [here](https://www.gsx.com/blog/bid/81096/enhance-your-powershell-experience-by-automatically-loading-scripts).

Also you need dependencies: [peco](https://github.com/peco/peco) and PowerShell, which can be
installed on different Linux distributions (on some of them with little tricks: ignore some
dependencies, link missing OpenSSH library to existing one or - better - install missing
OpenSSH library of mandatory version).

Usage
-----

First, create TAGS file:

```
tags -make
```

for current directory or:

```
tags -make ../TAGS
```

Also you can remove it with `tags -rm` or `tags -rm ../TAGS` (with path to file).

Before to query tags, you must to load it: `$t=tags -load` or `$t=tags -load ../TAGS` (or from another path).
Now `$t` contains all tags. So, you can show them with `$t` or `$t|ft`, etc. And, sure, to query:

```
$t|where {$_.Path -like '*Something*'}
```

you can use any typical query expressions for PowerShell, where criteria is attributes of module object.
Hierarchy is: `$t` is a list of modules, each module contains `Tags` which is a list of tags.
You can find demo [here](https://vimeo.com/video/286579355).

Features
========

* Create tags
* Remove tags
* Load tags
* Query tags modules and tags itself
* Navigate over tags and modules in UI, run different editors

Attributes
==========

Currently modules consists of:

- Path
- Name
- Size
- List of exported symbols
- List of imported modules
- List of tags

Each tag consists of:

- Name
- Line number
- Exported flag
- Module reference
- Type (one of Data/Newtype/Instance/Module/Function)
- Text (currently not implemented)
- Shortcuts for run/open (InVim/InLess/InEditor/InFs)

Status
======

P-o-C: mostly works, but exported flag is not always correct (sure), as well as list of exported symbols. Name of module mostly is
right. Script is planning to be used mostly as refactoring helper: for example to find some functions in some modules with exporting/
not-exporting symbols like something.