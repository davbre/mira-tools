
### infer-datapackage.rb
infer-datapackage.rb assumes [csvkit](https://csvkit.readthedocs.org) is
installed (csvkit version 0.9.1 at time of writing). It uses csvkit's csvstat
command to infer a datapackage.json file. This can be useful for creating a
skeleton datapackage.json file.

Examples:

`ruby infer-datapackage.rb /path/to/your/csvfiles/`

Overwrite any existing datapackage.json file with the "-o" switch:

`ruby infer-datapackage.rb -o /path/to/your/csvfiles/`

Specify a file which maps column names to types using the "-m" switch. This can
be used to override whatever type is inferred by the script:

`ruby infer-datapackage.rb /path/to/your/csvfiles/ -m metadata/known_types.yml`
