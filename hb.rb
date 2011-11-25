#!/usr/bin/ruby

require 'optparse'
require 'tmpdir'
require 'ostruct'

class Handbrake
  require 'fileutils'  
  require 'tools.rb'
  include Tools

  HANDBRAKE_CLI = File.expand_path("HandbrakeCLI")

  attr_accessor :options
  
  def initialize(options)
    @options = options
  end

  def readDvd()
    path = File.expand_path(options.input)
    output = %x["#{HANDBRAKE_CLI}" -i "#{path}" --scan -t 0 2>&1]
    main_feature_pattern = /\+ Main Feature/
    title_blocks_pattern = /\+ vts .*, ttn .*, cells .* \(([0-9]+) blocks\)/
    title_pattern = /\+ title ([0-9]+):/
    title_info_pattern = /\+ size: ([0-9]+x[0-9]+).*, ([0-9.]+) fps/
    audio_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\), ([0-9]+Hz), ([0-9]+bps)/
    subtitle_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\)/
    duration_pattern = /\+ duration: (.*)/
    chapter_pattern = /\+ ([0-9]+): cells .* duration (.*)/
    dvd = Dvd.new(path)
    title = nil
    output.each_line do |line|
      puts "### #{line}" if options.debug and options.verbose
      if line.match(title_pattern)
        info = line.scan(title_pattern)[0]
        title = Title.new(info[0])
        dvd.titles().push(title)
      end

      next if title.nil?

      if line.match(main_feature_pattern)
        title.mainFeature = true
      elsif line.match(title_blocks_pattern)
        info = line.scan(title_blocks_pattern)[0]
        title.blocks = info[0].to_i
      elsif line.match(title_info_pattern)
        info = line.scan(title_info_pattern)[0]
        title.size = info[0]
        title.fps = info[1]
      elsif line.match(duration_pattern)
        info = line.scan(duration_pattern)[0]
        title.duration = info[0]
      elsif line.match(chapter_pattern)
        info = line.scan(chapter_pattern)[0]
        chapter = Chapter.new(info[0])
        chapter.duration = info[1]
        title.chapters().push(chapter)
      elsif line.match(audio_pattern)
        info = line.scan(audio_pattern)[0]
        track = AudioTrack.new(info[0],info[2], info[1])
        title.audioTracks().push(track)
      elsif line.match(subtitle_pattern)
        info = line.scan(subtitle_pattern)[0]
        subtitle = Subtitle.new(info[0],info[2], info[1])
        title.subtitles().push(subtitle)
      end
    end
    return dvd
  end

  def ripDvd(dvd, titleMatcher, audioMatcher, subtitleMatcher)
    ripped = []
    output = options.output
    preset = options.preset
    mainFeatureOnly = options.mainFeatureOnly || false
    force = options.force || false
    skipDuplicates = options.skipDuplicates || false
    verbose = options.verbose || false
    debug = options.debug || false
    xtraArgs = options.xtra_args
    minLength = TimeTool::timeToSeconds(options.minLength)
    maxLength = TimeTool::timeToSeconds(options.maxLength)

    dvd.titles().each do |title|
      if titleMatcher.matches(title) and (!mainFeatureOnly or (mainFeatureOnly and title.mainFeature))
        puts "\n#{title}"
        tracks = audioMatcher.filter(title.audioTracks)
        subtitles = subtitleMatcher.filter(title.subtitles)
        
        duration = TimeTool::timeToSeconds(title.duration)
        if minLength >= 0 and duration < minLength
          puts "skipping title because it's duration is too short (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})"
          next
        end
        if maxLength >= 0 and duration > maxLength
          puts "skipping title because it's duration is too long (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})"
          next
        end
        if tracks.empty?() or tracks.length < audioMatcher.languages.length
          puts "skipping title because it contains not all wanted audio-tracks"
          next
        end
        if skipDuplicates and title.blocks() >= 0 and ripped.include?(title.blocks())
          puts "skipping because disc contains it twice"
          next
        end
        ripped.push(title.blocks())

        extra_arguments = xtraArgs
        outputFile = File.expand_path(output)
        outputFile = outputFile.gsub("#pos#", "%02d" % title.pos)
        outputFile = outputFile.gsub("#size#", title.size)
        outputFile = outputFile.gsub("#fps#", title.fps)
        outputFile = outputFile.gsub("#input#", File.basename(dvd.path()))
        
        command="\"#{HANDBRAKE_CLI}\""
        command << " --input \"#{dvd.path()}\""
        command << " --output \"#{outputFile}\""
        command << " --verbose" if verbose
        if not preset.nil? and not preset.empty? 
          command << " --preset \"#{preset}\""
        else
          # video
          vbr = 1500
          x264_quality = nil
          x264_quality_opts = nil
          x264_quality = "20.0"

          # iPod
          x264_quality_opts = "level=30:bframes=0:weightp=0:cabac=0:8x8dct=0:ref=1:vbv-maxrate=#{vbr}:vbv-bufsize=2500:analyse=all:me=umh:no-fast-pskip=1:psy-rd=0,0:subme=6:trellis=0"
          
          # https://forum.handbrake.fr/viewtopic.php?f=6&t=19426
          # ultrafast
          #x264_quality_opts = "ref=1:bframes=0:cabac=0:8x8dct=0:weightp=0:me=dia:subq=0:rc-lookahead=0:mbtree=0:analyse=none:trellis=0:aq-mode=0:scenecut=0:no-deblock=1"
          # superfast
          #x264_quality_opts = "ref=1:weightp=1:me=dia:subq=1:rc-lookahead=0:mbtree=0:analyse=i4x4,i8x8:trellis=0"
          # veryfast
          #x264_quality_opts = "ref=1:weightp=1:subq=2:rc-lookahead=10:trellis=0"
          # faster
          #x264_quality_opts = "ref=2:mixed-refs=0:weightp=1:subq=4:rc-lookahead=20"
          # fast
          #x264_quality_opts = "ref=2:weightp=1:subq=6:rc-lookahead=30"
          # slow
          #x264_quality_opts = "ref=5:b-adapt=2:direct=auto:me=umh:subq=8:rc-lookahead=50"
          # slower
          #x264_quality_opts = "ref=8:b-adapt=2:direct=auto:me=umh:subq=9:rc-lookahead=60:analyse=all:trellis=2"
          # veryslow
          #x264_quality_opts = "ref=16:bframes=8:b-adapt=2:direct=auto:me=umh:merange=24:subq=10:rc-lookahead=60:analyse=all:trellis=2"
          # placebo
          #x264_quality_opts = "ref=16:bframes=16:b-adapt=2:direct=auto:me=tesa:merange=24:subq=10:rc-lookahead=60:analyse=all:trellis=2:no-fast-pskip=1"
          command << " --encoder x264"
          if x264_quality.nil?
            command << " --vb #{vbr}"
            command << " --two-pass"
            command << " --turbo"
          else
            command << " --quality #{x264_quality}"
          end
          # tune encoder
          command << " -x "
          command << "#{x264_quality_opts}:" unless x264_quality_opts.nil?
          # append for iPod-compatibility
          command << "level=30:bframes=0:cabac=0:weightp=0:8x8dct=0"
          command << " --decomb"
          command << " --detelecine"
          command << " --maxWidth 1024"
          command << " --crop 0:0:0:0"
          # audio
          command << " --aencoder #{Array.new(tracks.length, "faac").join(",")}"
          command << " --arate #{Array.new(tracks.length, "Auto").join(",")}"
          command << " --mixdown #{Array.new(tracks.length, "dpl2").join(",")}"
          command << " --ab #{Array.new(tracks.length, "160").join(",")}"
          command << " --drc #{Array.new(tracks.length, "0.0").join(",")}"
          # common
          command << " --format mp4"
          command << " --markers"
          command << " --optimize"
        end
        command << " --title #{title.pos}"
        command << " --audio #{tracks.join(",")}"
        command << " --subtitle #{subtitles.join(",")}" if ! subtitles.empty?()
        command << " " << extra_arguments if not extra_arguments.nil?() and not extra_arguments.empty?
        command << " 2>&1"

        if ! File.exists? outputFile or force
          puts command
          if ! debug
            parentDir = File.dirname(outputFile)
            FileUtils.mkdir_p(parentDir) unless File.directory?(parentDir)
            system command
            # user should decide what to do...
            #File.rename("#{outputFile}.tmp", outputFile) if not File.exists? outputFile and File.exists? "#{outputFile}.tmp"
          end
        else
          puts "skipping title because \"#{outputFile}\" already exists"
        end
      end
    end
  end
end

class Chapter
  attr_accessor :pos, :duration
  def initialize(pos)
    @pos = pos.to_i
    @duration = "unknown"
  end

  def to_s
    "#{pos}. #{duration}"
  end
end

class Subtitle
  attr_accessor :pos, :lang, :desc
  def initialize(pos, lang, desc)
    @pos = pos.to_i
    @lang = lang
    @desc = desc
  end

  def to_s
    "#{pos}. #{desc} (#{lang})"
  end
end

class AudioTrack
  attr_accessor :pos, :lang, :desc
  def initialize(pos, lang, desc)
    @pos = pos.to_i
    @lang = lang
    @desc = desc
  end

  def to_s
    "#{pos}. #{desc} (#{lang})"
  end
end

class Title
  attr_accessor :pos, :audioTracks, :subtitles, :chapters, :size, :fps, :duration, :mainFeature, :blocks
  def initialize(pos)
    @pos = pos.to_i
    @blocks = -1
    @audioTracks = []
    @subtitles = []
    @chapters = []
    @size = "unknown"
    @fps = "unknown"
    @duration = "unknown"
    @mainFeature = false
  end

  def to_s
    alist = []
    for t in audioTracks
      alist.push(t.lang)
    end
    slist = []
    for s in subtitles
      slist.push(s.lang)
    end
    "title #{"%02d" % pos}: #{duration}, #{size}, #{fps} fps, main-feature: #{mainFeature()}, blocks: #{blocks}, chapters: #{chapters.length}, audio-tracks: #{alist.join(",")}, subtitles: #{slist.join(",")}"
  end
end

class Dvd
  attr_accessor :titles, :path
  def initialize(path)
    @titles = []
    @path = path
  end

  def to_s
    "#{path}"
  end
end

class DefaultMatcher
  attr_accessor :positions, :languages
  
  def initialize(positions, languages)
    @positions = positions
    @languages = languages
  end

  def matches(obj)
    
    if obj.respond_to?("pos") and ! positions().nil?() and ! positions().include?(obj.pos)
      return false
    end

    if obj.respond_to?("lang") and ! languages().nil?() and ! languages().include?(obj.lang)
      return false
    end

    return true
  end
  
  def filter(list, onlyFirst = true)
    if positions().nil?() and languages().nil?()
      return list
    end
    filtered = []
    if ! positions().nil?()
      positions().each do |p|
        list.each do |e|
          if e.respond_to?("pos") and (e.pos() == p or e.pos.eql? p)
            if ! filtered.include?(e.pos)
              filtered.push(e.pos())
              break if onlyFirstd
            end
          end
        end
      end
    end
    
    if ! languages().nil?()
      languages().each do |l|
        list.each do |e|
          if e.respond_to?("lang") and (e.lang() == l or e.lang.eql? l)
            if ! filtered.include?(e.pos)
              filtered.push(e.pos())
              break if onlyFirst
            end
          end
        end
      end
    end
 
    return filtered
  end
  
end

options = OpenStruct.new
optparse = OptionParser.new do |opts|
  
  opts.on("--input INPUT", "input-source") do |arg|
    options.input = arg
  end
  
  opts.on("--output OUTPUT", "output-directory") do |arg|
    options.output = arg
  end

  opts.on("--preset PRESET", "the preset to use") do |arg|
    options.preset = arg
  end

  opts.on("--main", "main-feature only") do |arg|
    options.mainFeatureOnly = arg
  end
  
  opts.on("--force", "force override of existing files") do |arg|
    options.force = arg
  end  

  opts.on("--titles TITLES", Array, "the titles languages") do |arg|
    options.titles = arg
  end
  
  opts.on("--min-length DURATION", "the minimum-track-length - format hh:nn:ss") do |arg|
    options.minLength = arg
  end

  opts.on("--max-length DURATION", "the maximum-track-length - format hh:nn:ss") do |arg|
    options.maxLength = arg
  end
  
  opts.on("--skip-duplicates", "skip duplicate tracks (checks bock-size)") do |arg|
    options.skipDuplicates = arg
  end

  opts.on("--audio LANGUAGES", Array, "the audio languages") do |arg|
    options.languages = arg
  end

  opts.on("--subtitles LANGUAGES", Array, "the subtitle languages") do |arg|
    options.subtitles = arg
  end
  
  opts.on("--check", "run check only and display information") do |arg|
    options.checkOnly = arg
  end
  
  opts.on("--xtra ARGS", "additional arguments for handbrake") do |arg|
    options.xtra_args = arg
  end
  
  opts.on("--debug", "enable debug-mode") do |arg|
    options.debug = arg
  end
  
  opts.on("--verbose", "enable verbose output") do |arg|
    options.verbose = arg
  end
      
  opts.on("--help", "Display this screen") do
    puts opts
    exit
  end
end

optparse.parse!(ARGV)

if ! options.titles.nil?()
  tmp = []
  titles.each do |t|
    range_pattern = /([0-9]+)-([0-9]+)/ 
    if t.match(range_pattern)
      range = t.scan(range_pattern)[0]
      rangeStart = range[0].to_i
      rangeEnd = range[1].to_i
      rangeStart.upto(rangeEnd) { |n| tmp.push(n) unless tmp.include?(n) } 
    else
      tmp.push(t.to_i) unless tmp.include?(t.to_i)
    end
  end
  titles = tmp
end

if options.languages.nil?()
  options.languages = ["deu"]
end
if options.subtitles.nil?()
  options.subtitles = []
end

if options.input.nil?() or (!options.checkOnly and options.output.nil?())
  puts optparse
  exit
end

if ! File.exist? options.input
  puts "\"#{options.input}\" does not exist"
  exit
end

hb = Handbrake.new(options)
dvd = hb.readDvd()

titleMatcher = DefaultMatcher.new(options.titles, nil) 
audioMatcher = DefaultMatcher.new(nil, options.languages)
subtitleMatcher = DefaultMatcher.new([], options.subtitles)

if options.checkOnly
  puts dvd
  dvd.titles().each do |t|
    puts "#{t}"
    puts "  audio-tracks:"
    t.audioTracks().each do |a|
      puts "    #{a}"
    end
    puts "  subtitles:"
    t.subtitles().each do |s|
      puts "    #{s}"
    end
  end
else
  hb.ripDvd(dvd, titleMatcher, audioMatcher, subtitleMatcher)
end