#!/usr/bin/ruby

require 'optparse'
require 'csv'
require 'ostruct'
require 'lib/tools.rb'
require 'lib/taggers.rb'
require 'iconv'

class Serienjunkies
  require 'rubygems'
  require 'hpricot'
  require 'open-uri'
  require 'singleton'
  include Singleton

  class SJInfo
    attr_accessor :name, :season, :episode, :title_de, :title_en, :descr, :sj_url
    def initialize(name, season, episode)
      @name = name
      @season = season
      @episode = episode
    end

    def to_s
      "%s - %02dx%02d - %s (%s)\n%s" % [@name, @season, @episode, @title_de, @title_en, @descr]
    end
  end
  URL = 'http://www.serienjunkies.de'
  
  #USER_AGENT = 'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; en-US; rv:1.9.1.2) Gecko/20090729 Firefox/3.5.2'
  if Tools::OS::windows?()
    USER_AGENT = 'Mozilla/5.0 (Windows; U; Windows NT 5.1; de; rv:1.8.0.1) Gecko/20060111 Firefox/1.5.0.1'
  else
    USER_AGENT = 'Mozilla/5.0 (X11; U; Linux i686; de-DE; rv:1.7.3) Gecko/20040924 Epiphany/1.4.4 (Ubuntu)'
  end
  
  def load(name, season, episode, url)
    e = "%dx%02d" % [season, episode]
    doc = loadUrl(url)

    info = SJInfo.new(name, season, episode)
    table = doc.search("table[@class=eplist]")
    elements = table.search("td[text()='#{e}']")
    raise "found no info for #{e} at #{url}" if elements.nil?

    elements.each do |td|
      tr = td.parent
      data = tr.search("td")
      raise "found not info for #{e} at #{url}" if data.size() < 4
      links = data[2].search("a")
      info.title_en = str(links[0].innerText()) unless links.empty? 

      links = data[3].search("a")
      info.title_de = str(links[0].innerText()) unless links.empty?
      
      if not links.empty?
        descr_link = links[0].get_attribute("href") 
        info.sj_url = str(URL + descr_link)
        info.descr = descr(URL + descr_link)
      end
    end
    return info
  end
  
  private
  
  def str(value)
    return nil if value.nil? or value.strip.empty?
    if Tools::OS::windows?
      begin
        v = Iconv.iconv('iso-8859-15', 'utf-8', value).first
      rescue
        v = value
      end
      value = v
    end 
    return value.strip
  end

  def descr(url)
    doc = loadUrl(url)
    raise "can not load #{url}" if doc.nil?
    table = doc.search("table[@id=epdetails]")
    summary_span = table.at("//span[@class=summary]")
    
    return nil if summary_span.nil? or summary_span.following_siblings.nil? or summary_span.following_siblings.empty?

    return str(summary_span.following_siblings.first.innerText())
  end

  def loadUrl(url)
    content = open(url, 'User-Agent' => USER_AGENT).read
    doc = Hpricot(content)
    return doc
  end
end

class TagDb
  attr_accessor :data, :dir, :db, :debug, :columns
  L = Tools::Loggers.console()
  
  ALWAYS_UPDATE_SJ_VALUES = true
  
  DB_NAME = "tagdb.csv"
  NAME = "name"
  SEASON = "season"
  DISC = "disc"
  TRACK = "track"
  EPISODE = "episode"
  TITLE = "title"
  TITLE_ORG = "title_org"
  DESCR = "descr"
  SJ_URL = "sj_url"
  SJ_ID = "sj_id"
  SJ_SEASON = "sj_season"
  SJ_EPISODE = "sj_episode"
  SJ_TITLE = "sj_title"
  SJ_TITLE_ORG = "sj_title_org"
  SJ_DESCR = "sj_descr"
  FILE_ID = "file_id"
  KNOWN_COLUMNS = [ FILE_ID, NAME, SEASON, DISC, TRACK, EPISODE, TITLE, TITLE_ORG, DESCR, SJ_ID, SJ_SEASON, SJ_EPISODE, SJ_URL, SJ_TITLE, SJ_TITLE_ORG, SJ_DESCR ]

  ID_PATTERN_STR = '[a-zA-Z0-9_-]+S(\d+)D(\d+)T(\d+)'

  def initialize(dir, debug)
    @data = {}
    @dir = dir
    @db = File.join(File.dirname(File.expand_path($0)), DB_NAME) 
    @debug = debug
    load()
    @columns = KNOWN_COLUMNS if columns.nil? or columns.empty?
    unknown_columns = @columns - KNOWN_COLUMNS
    if not unknown_columns.empty?
      L.warn("database contains unknown columns: #{unknown_columns.join(", ")}")
    end
    missing_columns = KNOWN_COLUMNS - @columns
    @columns = @columns + missing_columns if not missing_columns.empty?
  end
  
  def load()
    puts @db
    if File.exists? @db
      first = true
      CSV.open(@db, "r", ";") do |row|
        if first
          @columns = row
          first = false
          next
        end
        info = {}
        for i in 0..@columns.length
          info[@columns[i]] = row[i]
        end
        data[info[FILE_ID]] = info
      end
    end
  end
  
  def checkDuplicates
    duplicates = []
    ids = []
    data.each do |k,v|
      ids << v[FILE_ID] 
    end
    ids.each do |id|
      duplicates << id if ids.count(id) > 1 and not duplicates.include?(id)
    end
    raise "duplicate ids found #{duplicates.join(", ")}" if not duplicates.empty?
  end
  
  def save()
    checkDuplicates()
    k = data.keys.sort { |k1,k2|
      cmpMapEntry(data, k1, k2, [NAME, SEASON, EPISODE])
    }
    writer = CSV.open(db,"w", ";")
    begin
      writer << @columns
      k.each do |key|
        info = data[key]
        row = []
        for i in 0..@columns.length
          row[i] = info[@columns[i]]
        end
        writer << row
      end
    ensure
      writer.close
    end
  end
  
  def cmpMapEntry(map, k1, k2, valueKeys)
    valueKeys.each do |k|
      v1 = "#{map[k1][k]}"
      v2 = "#{map[k2][k]}"
      if v1 =~ /^\d+$/ and v2 =~ /^\d+$/
        v1 = v1.to_i
        v2 = v2.to_i
      end
      r = v1 <=> v2
      return r if r != 0
    end
    return k1 <=> k2
  end
  
  def updateTags(pattern, renamefiles = false)
    pattern = "**/*.mp4" if pattern.nil?  
    Dir["#{dir}/#{pattern}"].each do |f|
      next if not File.exists? f
      L.info("updating mp4-tags for #{f}")
      id = fileid(f)
      next if empty?(id)

      info = createTagMap(data[id])
      if info.nil?
        L.warn("found no tags for #{f}")
        next
      end
      cmd = TaggerFactory.newTagger().createCommand(f, info)
      if cmd.nil?
        L.warn("could not create command to tag file #{f}")
        next
      end
      cmd = Tools::Tee::command(cmd,File.expand_path("tag.log"),true)
      L.info("#{cmd}")
      %x[#{cmd}] if not debug
      titled_name = nil
      titled_name = "#{info[TITLE]}.#{info[FILE_ID]}.mp4" if not empty?(info[TITLE]) and not empty?(info[FILE_ID])
      titled_name.gsub!(/[\/:"*?<>|]+/, "_")
      titled_name = File.join(File.dirname(f), titled_name)
      if renamefiles and not empty?(titled_name) and not f.eql? titled_name
        if not File.exists?(titled_name)
          L.info("renaming file\n\tfrom: #{File.basename(f)}\n\tto  : #{File.basename(titled_name)}")
          File.rename(f, titled_name)
        else
          L.warn("could not rename #{f} to #{File.basename(titled_name)} because target already exists!")
        end
      end
    end
  end
  
  def createTagMap(data)
    return nil if data.nil?
    tags = data.dup
    copyMapEntry(tags,SJ_TITLE,TITLE)
    copyMapEntry(tags,SJ_TITLE_ORG,TITLE_ORG)
    copyMapEntry(tags,SJ_DESCR,DESCR)
    
    title = tags[TITLE]
    title = "%s - %02dx%02d - %s" % [tags[NAME], tags[SEASON], tags[EPISODE], title ]
    title = "%s (%s)" % [title, tags[TITLE_ORG]] if not empty?(tags[TITLE_ORG])
    tags[TITLE] = title

    tags[NAME] = nil 

    return tags
  end
  
  def copyMapEntry(map, from, to)
    map[to] = map[from] if empty?(map[to]) and not empty?(map[from])
  end
  
  def fileid(file)
    id = File.basename(file, ".*")
    id.gsub!(/^.*[.](#{ID_PATTERN_STR})$/, "\\1") if id =~ /^.*[.](#{ID_PATTERN_STR})$/
    return id
  end

  def updateDb(pattern = nil, sj = false)
    pattern = "**/*.mp4" if pattern.nil?
    Dir["#{dir}/#{pattern}"].each { |f|
      next if not File.exists? f
      L.info("updating database entry for #{f}")
      
      id = fileid(f)
      next if empty?(id)
      
      path = File.expand_path(f)
      path = path[dir.length + 1, path.length - dir.length] if path.start_with? dir
      path = path.split("/")

      info = data[id]
      info = {} if info.nil?

      info[NAME] = path[0]

      info[SEASON] = id.gsub(/#{ID_PATTERN_STR}/, "\\1")
      info[DISC] = id.gsub(/#{ID_PATTERN_STR}/, "\\2")
      info[TRACK] = id.gsub(/#{ID_PATTERN_STR}/, "\\3")
      info[FILE_ID] = id if empty?(info[FILE_ID])
      updateInfoFromSerienjunkies(info) if sj
      data[info[FILE_ID]] = info
    }
    
    # update episodes
    last_season = -1
    episode = -1
    k = data.keys.sort
    k.each do |key|
      info = data[key]

      season = info[SEASON].to_i

      if not info[EPISODE].nil?
        episode = info[EPISODE].to_i
        next
      end

      episode = 1 if not season == last_season
      info[EPISODE] = episode.to_s

      episode += 1
      last_season = season
    end

    save
  end
  
  def updateInfoFromSerienjunkies(info)
    return if empty?(info[SEASON]) or empty?(info[EPISODE]) or empty?(info[SJ_ID]) or empty?(info[NAME])

    complete = true
    [SJ_TITLE, SJ_TITLE_ORG, SJ_URL].each do |c|
      complete = false if empty?(info[c])
    end
    return if complete and not ALWAYS_UPDATE_SJ_VALUES

    season = info[SEASON]
    season = info[SJ_SEASON] unless empty?(info[SJ_SEASON])
    episode = info[EPISODE]
    episode = info[SJ_EPISODE] unless empty?(info[SJ_EPISODE])
    
    sj = Serienjunkies.instance.load(info[NAME], season.to_i, episode.to_i, Serienjunkies::URL + '/' + info[SJ_ID] + '/alle-serien-staffeln.html')
    return if sj.nil?

    info[SJ_TITLE] = sj.title_de() if not empty?(sj.title_de())
    info[SJ_TITLE_ORG] = sj.title_en() if not empty?(sj.title_en())
    #infoSJ_[DESCR] = sj.descr() if not empty?(sj.descr())
    info[SJ_URL] = sj.sj_url() if not empty?(sj.sj_url())
  end
  
  def empty?(value)
    value.nil? or value.strip.empty? 
  end
end

options = OpenStruct.new
options.updatedb = false
options.updatetags = false
options.pattern = nil
options.debug = false
options.sj = false
options.rename = false
options.directory = nil

optparse = OptionParser.new do |opts|
  opts.on("--update-db", "update tag-database") do |arg|
    options.updatedb = arg
  end
  opts.on("--sj", "update database with values from serienjunkies.de") do |arg|
    options.sj = arg
  end
  opts.on("--update-tags", "update tags in files") do |arg|
    options.updatetags = arg
  end
  opts.on("--update-names", "update filesnames according to the tags") do |arg|
    options.rename = arg
  end
  opts.on("--dir DIRECTORY", "the parent-directory containing the database and mp4-files") do |arg|
    options.directory = arg
  end
  opts.on("--files PATTERN", "the pattern for the files to update e.g. firefly/**/*.mp4") do |arg|
    options.pattern = arg
  end
  opts.on("--debug", "debug-mode (log commands without executing)") do |arg|
    options.debug = arg
  end
  opts.on("--help", "Display this screen") do
    puts opts
    exit
  end
end

optparse.parse!(ARGV)

if options.directory.nil?
  puts opts
  exit
end

db = TagDb.new(options.directory, options.debug)
db.updateDb(options.pattern, options.sj) if options.updatedb
db.updateTags(options.pattern, options.rename) if options.updatetags
