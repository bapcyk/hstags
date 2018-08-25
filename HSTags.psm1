# Example:
# tags -make -path [/some/path/TAGS]
# $t  = tags -load -path [/some/path/TAGS]
# ($t|where{$_.Path -like "*GitCommand.hs"}).Tags[-1].InVim|run
# ($t|where{$_.Path -like "*GitCommand.hs"}).Tags[-1].Module.Path|ii
#   ii - Invoke-Item
# $t.Tags|%{$_.Module.Path}|uniq|peco|ii
# menu $t -fs
# menu $t -vim

# . $PSScriptRoot/QHaskVars.ps1

enum YN {
    Yes
    No
    Unk
}

function ShortPath {
    Param(
        [string]$path,
        [string]$cwd = ""
    )
    if (!$cwd) {
        $cwd = (Get-Item -Path ".").FullName
    }
    $cwd = $cwd -replace "/$", ""
    $h = $env:HOME -replace "/$", ""
    $path -replace $cwd, "." -replace $h, "~"
}

function LongPath {
    Param(
        [string]$path,
        [string]$cwd = ""
    )
    if (!$cwd) {
        $cwd = (Get-Item -Path ".").FullName
    }
    $cwd = ($cwd -replace "/$", "") + "/"
    $h = ($env:HOME -replace "/$", "") + "/"
    $path -replace "./", $cwd -replace "~/", $h
    # FIXME
}

class Cmd {
    [string]$Cmd
    [string[]]$Params

    Cmd([string[]]$pars) {
        $this.Cmd = $pars[0]
        $this.Params = $pars[1..($pars.Count-1)]
    }

    [string]ToString() {
        return ((,$this.Cmd) + $this.Params) -join " "
    }
}

class Mod {
    [string]$Path
    [string]$Name
    [int]$Size
    [string[]]$Exported
    [string[]]$Imported
    [Tag[]]$Tags

    Mod($path, $size) {
        $this.Path = $path
        $this.Size = $size
        $this.Exported = @()
        $this.Imported = @()
        $this.Tags = @()
    }

    [string]ToString() {
        return ShortPath $this.Path
    }

}

enum TagType {
    Data
    Newtype
    Instance
    Module
    Function
}

#function CmpTagTypes {
#    [CmdletBinding()]
#    Param(
#        [object]$oth,
#        [Parameter(ValueFromPipeline)]
#        [TagType]$me
#    )
#
#    $res = switch -WildCard ($oth.ToString()) {
#        "dat*" { $me -eq [TagType]::Data }
#        "new*" { $me -eq [TagType]::Newtype }
#        "in*"  { $me -eq [TagType]::Instance }
#        "mod*" { $me -eq [TagType]::Module }
#        "fun*" { $me -eq [TagType]::Function }
#    }
#    return $res
#}

class Tag {
    [string]$Name
    [int]$Ln
    [YN]$Exported
    [Mod]$Module
    [TagType]$Type
    [string]$Text

    # Properties that require initialization
    [string[]]$InVim
    [string[]]$InLess
    [string[]]$InEditor
    [string[]]$InFs

    [string]ToTitle() {
        $exp = switch ($this.Exported) {
            "Yes" { "+" }
            "No"  { "-" }
            "Unk" { "?" }
        }
        return "{0,-9} {1} {2}, {3}" -f $this.Type, $exp, $this.Name, $this.Ln
    }

    Init() {
        $editor = ($env:EDITOR)
        $this.InVim = "vim", ("+{0}" -f $this.Ln), $this.Module.Path
        $this.InLess = "less", "-N", ("+{0}" -f $this.Ln), $this.Module.Path
        $this.InFs = "xdg-open", $this.Module.Path # FIXME
        $this.InEditor = $editor, $this.Module.Path
    }

    [string[]]InSmth([string]$in) {
        switch ($in) {
            "vim" { return $this.InVim }
            "less" { return $this.InLess }
            "fs" { return $this.InFs }
            "editor" { return $this.InEditor }
            default { return $null }
        }
        return $null
    }
}

function ResolveCmd($some)
{
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'
    try { (Get-Command $some).Source }
    catch { "" }
    finally { $ErrorActionPreference=$oldPreference }
}

function run {
<#
.SYNOPSIS
...|run
.EXAMPLE
$sometag.InVim|run
.DESCRIPTION
Runs Cmd object
.PARAMETER cmd
command to run (pipelined)
#>
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline)]
        [string[]]$what
    )
    Begin { $arr = [System.Collections.ArrayList]@() }
    Process { [void]$arr.Add($what) }
    End {
        if ($arr.Length -gt 0) {
            $c = [Cmd]::new($arr)
            & $c.Cmd $c.Params
        } else {
            write-host "Nothing to run"
        }
    }

}

function FindTAGS($dir) {
<#
.SYNOPSIS
FindTAGS /some/path
.EXAMPLE
(FindTAGS ../automation).FullName
.DESCRIPTION
Finds recursively TAGS file
.PARAMETER dir
Folder to search. Default: current working directory
#>
    Get-ChildItem -Path $dir -Recurse | Where-Object { $_.Name -eq 'TAGS' }
}

function AllHaskellFiles($dir) {
<#
.SYNOPSIS
AllHaskellFiles /some/path
.EXAMPLE
AllHaskellFiles /some/path|foreach {$_.Name }
.DESCRIPTION
Returns recursively all Haskell files in folder
.PARAMETER dir
Folder to search. Default: current working directory
#>
    Get-ChildItem -Path $dir -Recurse -Filter "*.hs"
}

enum TPState {
    Init
    FileNext
    TagNext
}

# Supposes only spaces, not tabs
function LineIndent([string]$ln) {
    $res = ($ln|select-string "^\s*" -AllMatches).Matches
    if ($res.Length -gt 0) {
        return $res[0].Length
    } else {
        return 0
    }
}

function FirstWord([string]$ln) {
    $res = ($ln|select-string "^\w+\b" -AllMatches).Matches
    if ($res.Length -gt 0) {
        return $res[0]
    }
}

class TAGSParser {
    [TPState]$State
    [string]$TAGS

    TAGSParser([string]$tags) {
        $this.TAGS = $tags
    }

    [Tag]ParseTagLine([string]$line, [Mod]$mod) {
        $fragment, $info = $line.Split(0x7f -as [char])
        $name, $lines = $info.Split(0x01 -as [char])
        $lines = $lines.Trim()
        $ln0, $ln1 = $lines.Split(",")
        $name = $name.Trim().Split("=>")
        $name = if ($name.Length -gt 1) { $name[1].Trim() } else { $name[0] }
        $name = $name.Replace("-", ".")
        $ln0 = [convert]::ToInt32($ln0, 10)
        $ln1 = [convert]::ToInt32($ln1, 10)
        $exported =
          if ($mod) {
              if ($mod.Exported.Contains($name)) { [YN]::Yes }
              else                               { [YN]::Unk }
          } else { [YN]::No }
        $type = switch -WildCard ($fragment) {
            "data *"     { [TagType]::Data }
            "newtype *"  { [TagType]::Newtype }
            "instance *" { [TagType]::Instance }
            "module *"   { [TagType]::Module }
            default      { [TagType]::Function }
        }
        $text = ""
        #$text = $this.UntilNextBlock($mod.Path, $ln1)
        #$text = $this.ReadLine($mod.Path, $ln1)
        $tag = [Tag]@{Name=$name
                      Ln=$ln1
                      Exported=$exported
                      Module=$mod
                      Type=$type
                      Text=$text
                     }
        $tag.Init()
        return $tag
    }

    [string]ReadLine([string]$filename, [int]$ln) {
        $curln = 0
        foreach ($line in Get-Content $filename) {
            if ($curln -eq $ln) { return $line }
            else { $curln++ }
        }
        return ""
    }

    # Very slow; seems buggy
    [string]UntilNextBlock([string]$filename, [int]$ln) {
        $curln = 0
        $indent = 0
        $st = 0
        $tok = ""
        $lines = [System.Collections.ArrayList]@()
        foreach ($line in Get-Content $filename) {
            switch ($st) {
                0 {
                    if ($curln -eq $ln) {
                        $indent = LineIndent($line)
                        $tok = FirstWord($line)
                        $lines.Add($line)
                        $st = 1
                    } else {
                        $curln++
                    }
                }
                1 {
                    $indent1 = LineIndent($line)
                    $tok1 = FirstWord($line)
                    if ($indent1 -lt $indent) {
                        #break
                        return $lines -join "; "
                    } elseif ($indent1 -eq $indent -and $tok1 -eq $tok) {
                        $lines.Add($line)
                    } else {
                        $lines.Add($line)
                    }
                }
            }
        }
        return $lines -join "; "
    }

    [Mod]ParseModFile([Mod]$mod) {
        $text = [IO.File]::ReadAllText($mod.Path)
        # find module name, exported symbols
        $matched = [regex]::Match($text, "(?smi)module\s+([^ ]+)\s*\((.*?)\)\s+where")
        if ($matched.success) {
            $mod.Name = $matched.groups[1].value.Trim()
            $cont = $matched.groups[2].value
            $exported = $cont|Select-String -Pattern "[^ \,]+" -AllMatches | % { $_.Matches | % { $_.Value }  }
            $exported = $exported | % { $_.Trim() } | where { $_ -and $_ -ne '(..)' }
            $mod.Exported = $exported
        }
        $imports = $text|Select-String -Pattern "(?smi)import\s+(qualified\s+)?([^ \n\r]+)" -AllMatches | % { $_.Matches }
        $imported = [System.Collections.ArrayList]@()
        foreach ($imp in $imports) {
            #write-host "grp len:" + $imp.Groups.Count + $imp.Groups[2]
            $imported.Add($imp.Groups[2].Value.Trim())
        }
        $mod.Imported = $imported
        return $mod
    }

    [Mod[]]Parse() {
        $this.State = [TPState]::Init
        $mod = $null
        $mods = [System.Collections.ArrayList]@()
        $atags = $null
        foreach ($line in Get-Content $this.TAGS) {
            switch ($this.State) {
                "Init" {
                    if ($line -match '\x0C') { $this.State = [TPState]::FileNext }
                    else { $this.State = [TPState]::Init }
                }
                "FileNext" {
                    if ($mod -and $atags) {
                        $mod.Tags = $atags
                    }
                    $modpath, $modsize = $line.Split(",")
                    $atags = [System.Collections.ArrayList]@()
                    $mod = [Mod]::new($modpath, [convert]::ToInt32($modsize, 10))
                    $mod = $this.ParseModFile($mod)
                    $mods.Add($mod)
                    $this.State = [TPState]::TagNext
                }
                "TagNext" {
                    if ($line -match '\x0C') { $this.State = [TPState]::FileNext }
                    else {
                        $tag = $this.ParseTagLine($line, $mod)
                        $atags.Add($tag)
                    }
                }
            }
        }
        return $mods
    }
}

function MakeTags($path) {
    $dir = [System.IO.Path]::GetDirectoryName($path)
    "stack", "exec", "hasktags", "--", "-eR", $dir, "-f", $path|run
}

function ParseTags($path) {
<#
.SYNOPSIS
ParseTags
.EXAMPLE
ParseTags ../TAGS
.DESCRIPTION
Parses TAGS file. If it does not exist, creates it first (with hashtags).
.PARAMETER path
Path to TAGS file. May be relative.
#>
    $parser = [TAGSParser]::new($path)
    #if(![System.IO.File]::Exists($path)) {
    $parser.Parse()
}

function tags {
    param (
        [switch]
        [bool]$make,

        [switch]
        [bool]$load,

        [switch]
        [bool]$rm,

        [string]$path="./TAGS"
    )
    if ($make) {
        return MakeTags($path)
    }
    elseif ($rm) {
        Remove-Item -Path $path
        write-host "$path was removed"
    }
    else {
        return ParseTags($path)
    }
}

class RunMenu {
    [Mod[]]$Mods

    [string[]]Tags() {
        $cwd = (Get-Item -Path ".").FullName
        $cwd = $cwd -replace "/$", ""
        $res = [System.Collections.ArrayList]@()
        foreach ($mod in $this.Mods) {
            #$p = ShortPath $mod.Path $cwd
            $p = $mod.Path
            foreach ($tag in $mod.Tags) {
                [void]$res.Add("$($tag.Name) -- $($tag.Ln) -- $p")
            }
        }
        return $res
    }
}

function menu {
    Param(
        [switch]
        [bool]$vim,

        [switch]
        [bool]$less,

        [switch]
        [bool]$fs,

        [switch]
        [bool]$editor,

        [Mod[]]$mods
    )

    if ($vim) { $runIn = "vim" }
    elseif ($less) { $runIn = "less" }
    elseif ($fs) { $runIn = "fs" }
    else { $runIn = "editor" }

    $rm = [RunMenu]@{Mods=$mods}
    $sel = ($rm.Tags()|peco --initial-filter Fuzzy).Split(" -- ")
    $n, $l, $p = $sel
    #$lp = LongPath $sel[2]
    $found = $mods | % { $_.Tags | where { $_.Name -eq $n -and $_.Ln -eq $l -and $_.Module.Path -eq $p} }
    switch ($found.Length) {
        1 { $found[0].InSmth($runIn) | run }
        0 { throw "Internal error: selected item can not be found" }
        default { $found[0].InSmth($runIn) | run
                  write-host "First tag was selected"
                }
    }
}
