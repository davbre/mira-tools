#!/usr/bin/env ruby
require 'optparse'
require 'open3'
require 'fileutils'
require 'json'
require 'pp'
require 'pry'
require 'yaml'

options = {}

# Types returned by csvkit mapped to types expected by JSON table
# schema (dataprotocols.org/json-table-schema/)
type_map = {
  "bool" => "boolean",
  "int" => "integer",
  "float" => "number",
  "datetime.datetime" => "datetime",
  "datetime.date" => "date",
  "datetime.time" => "time",
  "unicode" => "string",
  "string" => "string", # not sure this exists but just in case
  "NoneType" => "null"
  }

optparse = OptionParser.new do|opts|
  # Set a banner, displayed at the top
  # of the help screen.
  opts.banner = "Usage: optparse1.rb [options] file1 file2 ..."

  options[:overwrite] = false
  opts.on( '-o', '--overwrite', 'Overwrite existing datapackage.json if it exists') do
    options[:overwrite] = true
  end

  options[:typemap] = {}
  opts.on( '-m', '--typemap /path/to/YAML/TYPEMAP', 'YAML file mapping columns to their types, e.g. variable_name: string') do |tm|
    options[:typemap] = YAML.load(File.read(tm))
  end

  # Define the options, and what they do
  options[:verbose] = false
  opts.on( '-v', '--verbose', 'Output more information' ) do
    options[:verbose] = true
  end

  options[:remove_bom] = false
  opts.on('-r', '--remove-bom', "Remove inital BOM characters from CSV files") do |f|
    options[:remove_bom] = true
  end

  # opts.on('-e', '--extension', "Specify the csv file extension")
  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end

end

# Parse the command-line. Remember there are two forms
# of the parse method. The 'parse' method simply parses
# ARGV, while the 'parse!' method parses ARGV and removes
# any options found there, as well as any parameters for
# the options. What's left is the list of files to resize.
optparse.parse!

if ARGV.length != 1
  raise OptionParser::MissingArgument, "You must specify an absolute or relative path to your CSV files"
end

# rel_dir = File.expand_path(File.dirname(__FILE__)) + "/#{ARGV[0]}/"
rel_dir = "/#{ARGV[0]}/"

dp_file = rel_dir + "datapackage.json"
if File.file?(dp_file) and !options[:overwrite]
  raise "ERROR: datapackage.json already exists! (Delete and re-run if necessary or use the --overwrite switch to explicitly overwrite datapackage.json.)"
end


# remove BOM characters from csv files:
# http://stackoverflow.com/questions/1068650/using-awk-to-remove-the-byte-order-mark
if options[:remove_bom]
  # in all csv files in the specified directory (no subdirectories (maxdepth option)),
  # create a backup and remove the initial BOM characters.
  sed_command = "find #{rel_dir} -type f -maxdepth 1 -name \"*.csv\" -exec sed -i.bak '1 s/^\\xef\\xbb\\xbf//' {} \\;"
  %x[sed_command]
end


# guess the delimiter (http://stackoverflow.com/a/14695355)
COMMON_DELIMITERS = [',',"\t",';',"|","^"]

def sniff(path)
  first_line = File.open(path).first
  return nil unless first_line
  snif = {}
  COMMON_DELIMITERS.each {|delim|snif[delim]=first_line.count(delim)}
  snif = snif.sort {|a,b| b[1]<=>a[1]}
  snif.size > 0 ? snif[0][0] : nil
end

datapackage = {
  :name => "--NAME--",
  :title => "--TITLE--",
  :resources => [ ]
  }
ENV['LC_CTYPE']='en_US.UTF-8'

# create datapackage.json, see http://data.okfn.org/doc/tabular-data-package
Dir.glob(rel_dir + "*.csv") do |fname|

  dp_table = {}

  puts "Looking at #{fname}"

  # separate min and max commands as they are not always output when all information is requested
  comm_all = "csvstat -y 2048 -e utf-8 \"#{fname}\""
  comm_min = "csvstat --min -y 2048 -e utf-8 \"#{fname}\""
  comm_max = "csvstat --max -y 2048 -e utf-8 \"#{fname}\""

  o_all, e_all, s_all = Open3.capture3("#{comm_all}")
  o_min, e_min, s_min = Open3.capture3("#{comm_min}")
  o_max, e_max, s_max = Open3.capture3("#{comm_max}")

  column_names = o_all.to_enum(:scan, /(?<=\d\.)\s+\S+?(?=\n)/).map { Regexp.last_match.to_s.downcase.gsub(/\s+/,'') }
  column_types = o_all.to_enum(:scan, /(?<=\s\<type\s')[\w|\.]+?(?='\>\n)/).map { Regexp.last_match.to_s.downcase.gsub(/\s+/,'') }
  column_mins = o_min.to_enum(:scan, /:\K.*\n/).map { |m| m.gsub(/\s+/,'') }
  column_maxs = o_max.to_enum(:scan, /:\K.*\n/).map { |m| m.gsub(/\s+/,'') }

  # check that column attribute arrays are all of the same length
  # if [column_names.length,column_types.length,column_maxs.length,column_mins.length].uniq.length != 1
  #   binding.pry
  #   raise "ERROR: Failed to align your csv column attributes. Script needs attention!"
  # end

  dp_table[:path] = File.basename(fname)
  dp_table[:format] = "csv"
  dp_table[:dialect] = { "delimiter" => sniff(fname) }
  dp_table[:mediatype] = "text/csv"

  dp_table[:schema] = {}
  dp_table[:schema][:fields] = []
  column_names.each_with_index do |col,i|
    # http://dataprotocols.org/json-table-schema/
    unless type_map.has_key? column_types[i]
      raise "ERROR: Unexpected type returned by csvstat: #{column_types[i]}. Update script's type mapping!"
    end

    # sometimes csvkit doesn't give us what we want so we use 'known types' to assign a type
    field_type = (options[:typemap][column_names[i]].nil?) ? type_map[column_types[i]] : options[:typemap][column_names[i]]

    fields = {
     :name => col,
     :type => field_type
    }

    # if ["int", "float", "datatime.datetime", "datetime.date", "datetime.time"].include? column_types[i]
    #   fields[:constraints] = { :minimum => column_mins[i],:maximum => column_maxs[i] }
    # end

    dp_table[:schema][:fields] << fields
  end

  datapackage[:resources] << dp_table

end


# write datapackage.json
File.open(dp_file,"w") do |f|
  f.write(JSON.pretty_generate(datapackage))
end
