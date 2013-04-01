require 'fileutils'
require './lib/tools.rb'

module HandbrakeCLI
  class HBOptions
    attr_accessor :input, :output, :force,
                  :ipodCompatibility, :enableAutocrop,
                  :languages, :audioMixdown, :audioCopy,
                  :audioMixdownEncoder, :audioMixdownBitrate, :audioMixdownMappings,
                  :maxHeight, :maxWidth, :subtitles, :preset, :mainFeatureOnly, :titles, :chapters,
                  :minLength, :maxLength, :skipDuplicates,
                  :onlyFirstTrackPerLanguage, :skipCommentaries,
                  :checkOnly, :xtra_args, :debug, :verbose,
                  :x264profile, :x264preset, :x264tune,
                  :testdata, :preview
  end

  class Handbrake
    include Tools
  
    HANDBRAKE_CLI = File.expand_path("#{Tools::Common::basedir()}/tools/handbrake/#{Tools::OS::platform().to_s.downcase}/HandBrakeCLI")
  
    AUDIO_ENCODERS = %w(ca_aac ca_haac faac ffaac ffac3 lame vorbis ffflac)
    AUDIO_MIXDOWNS = %w(mono stereo dpl1 dpl2 6ch)
    AUDIO_MIXDOWN_DESCR = {
      "mono" => "Mono",
      "stereo" => "Stereo",
      "dpl1" => "Dolby Surround",
      "dpl2" => "Dolby Pro Logic II",
      "6ch" => "5.1"
    }
  
    X264_PROFILES = %w(baseline main high high10 high422 high444)
    X264_PRESETS = %w(ultrafast superfast veryfast faster fast medium slow slower veryslow placebo)
    X264_TUNES = %w(film animation grain stillimage psnr ssim fastdecode zerolatency)
  
    def self.getPresets()
      cmd = "\"#{HANDBRAKE_CLI}\" --preset-list 2>&1"
      output = %x[#{cmd}]
      preset_pattern = /\+ (.*?): (.*)/
      result = {}
      output.each_line do |line|
        next if not line =~ preset_pattern
        info = line.scan(preset_pattern)[0]
        result[info[0].strip] = info[1].strip
      end
      return result
    end
  
    def self.readInfo(input, debug = false, testdata = nil)
      path = File.expand_path(input)
      cmd = "\"#{HANDBRAKE_CLI}\" -i \"#{path}\" --scan --title 0 2>&1"
      if !testdata.nil? and File.exists?(testdata)
        output = File.read(testdata)
      else
        output = %x[#{cmd}]
      end
      if !testdata.nil? and !File.exists?(testdata)
        File.open(testdata, 'w') { |f| f.write(output) }
      end
  
      dvd_title_pattern = /libdvdnav: DVD Title: (.*)/
      dvd_alt_title_pattern = /libdvdnav: DVD Title \(Alternative\): (.*)/
      dvd_serial_pattern = /libdvdnav: DVD Serial Number: (.*)/
      main_feature_pattern = /\+ Main Feature/
  
      title_blocks_pattern = /\+ vts .*, ttn .*, cells .* \(([0-9]+) blocks\)/
      title_pattern = /\+ title ([0-9]+):/
      title_info_pattern = /\+ size: ([0-9]+x[0-9]+).*, ([0-9.]+) fps/
      in_audio_section_pattern = /\+ audio tracks:/
      audio_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\), ([0-9]+Hz), ([0-9]+bps)/
      file_audio_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\)/
      in_subtitle_section_pattern = /\+ (subtitles|subtitle tracks):/
      subtitle_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\)/
      duration_pattern = /\+ duration: (.*)/
      chapter_pattern = /\+ ([0-9]+): cells (.*), ([0-9]+) blocks, duration (.*)/
  
      source = MovieSource.new(path)
      title = nil
  
      in_audio_section = false
      in_subtitle_section = false
      has_main_feature = false
      output.each_line do |line|
        puts "out> #{line}" if debug
  
        if line.match(dvd_title_pattern)
          puts "> match: dvd-title" if debug
          info = line.scan(dvd_title_pattern)[0]
          source.title = info[0].strip
        elsif line.match(dvd_alt_title_pattern)
          puts "> match: dvd-alt-title" if debug
          info = line.scan(dvd_alt_title_pattern)[0]
          source.title_alt = info[0].strip
        elsif line.match(dvd_serial_pattern)
          puts "> match: dvd-serial" if debug
          info = line.scan(dvd_serial_pattern)[0]
          source.serial = info[0].strip
        elsif line.match(in_audio_section_pattern)
          in_audio_section = true
          in_subtitle_section = false
        elsif line.match(in_subtitle_section_pattern)
          in_audio_section = false
          in_subtitle_section = true
        elsif line.match(title_pattern)
          puts "> match: title" if debug
          info = line.scan(title_pattern)[0]
          title = Title.new(info[0])
          source.titles().push(title)
        end
  
        next if title.nil?
  
        if line.match(main_feature_pattern)
          puts "> match: main-feature" if debug
          title.mainFeature = true
          has_main_feature = true
        elsif line.match(title_blocks_pattern)
          puts "> match: blocks" if debug
          info = line.scan(title_blocks_pattern)[0]
          title.blocks = info[0].to_i
        elsif line.match(title_info_pattern)
          puts "> match: info" if debug
          info = line.scan(title_info_pattern)[0]
          title.size = info[0]
          title.fps = info[1]
        elsif line.match(duration_pattern)
          puts "> match: duration" if debug
          info = line.scan(duration_pattern)[0]
          title.duration = info[0]
        elsif line.match(chapter_pattern)
          puts "> match: chapter" if debug
          info = line.scan(chapter_pattern)[0]
          chapter = Chapter.new(info[0])
          chapter.cells = info[1]
          chapter.blocks = info[2]
          chapter.duration = info[3]
          title.chapters().push(chapter)
        elsif in_audio_section and line.match(audio_pattern)
          puts "> match: audio" if debug
          info = line.scan(audio_pattern)[0]
          track = AudioTrack.new(info[0], info[1])
          if info[1].match(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)
            info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)[0]
            track.codec = info2[0]
            track.comment = info2[1]
            track.channels = info2[2]
          elsif info[1].match(/\((.*?)\)\s*\((.*?)\)\s*/)
            info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*/)[0]
            track.codec = info2[0]
            track.channels = info2[1]
          end
          track.lang = info[2]
          track.rate = info[3]
          track.bitrate = info[4]
          title.audioTracks().push(track)
        elsif in_audio_section and line.match(file_audio_pattern)
          puts "> match: audio" if debug
          info = line.scan(file_audio_pattern)[0]
          track = AudioTrack.new(info[0], info[1])
          if info[1].match(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)
            info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)[0]
            track.codec = info2[0]
            track.comment = info2[1]
            track.channels = info2[2]
          elsif info[1].match(/\((.*?)\)\s*\((.*?)\)\s*/)
            info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*/)[0]
            track.codec = info2[0]
            track.channels = info2[1]
          end
          track.lang = info[2]
          title.audioTracks().push(track)
        elsif in_subtitle_section and line.match(subtitle_pattern)
          puts "> match: subtitle" if debug
          info = line.scan(subtitle_pattern)[0]
          subtitle = Subtitle.new(info[0], info[1], info[2])
          if info[1].match(/\((.*?)\)/)
            info2 = info[1].scan(/\((.*?)\)/)[0]
            subtitle.comment = info2[0]
          end
          title.subtitles().push(subtitle)
        end
      end
      if not has_main_feature
        longest = nil
        source.titles.each do |t|
          if longest.nil? 
            longest = t
            next
          end
          longest_duration = TimeTool::timeToSeconds(longest.duration)
          title_duration = TimeTool::timeToSeconds(t.duration)
          longest = t if title_duration > longest_duration
        end
        longest.mainFeature = true if not longest.nil?
      end
      return source
    end
    
    def self.getMixdown(track, mappings, default)
      descr = "#{track.descr}"
      if not mappings.nil?
        mappings.each do |r,m|
          return m if descr =~ /#{r}/
        end
      end
      return default
    end
  
    def self.convert(options, titleMatcher, audioMatcher, subtitleMatcher)
      source = Handbrake::readInfo(options.input, options.debug && options.verbose, options.testdata)
      created = []
      if options.checkOnly
        puts source.info
        return created
      end
      
      if source.titles.empty?
        Tools::CON::info("#{source.path} contains no titles")
        return created
      end
  
      converted = []
      if options.minLength.nil?
        minLength = -1
      else
        minLength = TimeTool::timeToSeconds(options.minLength)
      end
      if options.maxLength.nil?
        maxLength = -1
      else
        maxLength = TimeTool::timeToSeconds(options.maxLength)
      end
  
      source.titles().each do |title|
        Tools::CON.info("checking #{title}")
        
        if options.mainFeatureOnly and not title.mainFeature
          Tools::CON.info("skipping title because it's not the main-feature")
          next
        elsif not titleMatcher.matches(title)
          Tools::CON.info("skipping unwanted title")
          next
        end
  
        tracks = audioMatcher.filter(title.audioTracks)
        subtitles = subtitleMatcher.filter(title.subtitles)
  
        duration = TimeTool::timeToSeconds(title.duration)
        if minLength >= 0 and duration < minLength
          Tools::CON.info("skipping title because it's duration is too short (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})")
          next
        end
        if maxLength >= 0 and duration > maxLength
          Tools::CON.info("skipping title because it's duration is too long (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})")
          next
        end
        if tracks.empty?()
          Tools::CON.info("skipping title because it contains no audio-tracks (available: #{title.audioTracks})")
          next
        end
        if options.skipDuplicates and not title.blocks().nil? and title.blocks() >= 0 and converted.include?(title.blocks())
          Tools::CON.info("skipping because source contains it twice")
          next
        end
        
        converted.push(title.blocks()) if not title.blocks().nil?
  
        outputFile = File.expand_path(options.output)
        outputFile.gsub!("#pos#", "%02d" % title.pos)
        outputFile.gsub!("#size#", title.size || "")
        outputFile.gsub!("#fps#", title.fps || "")
        outputFile.gsub!("#ts#", Time.new.strftime("%Y-%m-%d_%H_%M_%S"))
        outputFile.gsub!("#title#", source.name)
        if not options.force
          if File.exists?(outputFile) or Dir.glob("#{File.dirname(outputFile)}/*.#{File.basename(outputFile)}").size() > 0
            Tools::CON.info("skipping title because \"#{outputFile}\" already exists")
            next
          end
        end
  
        Tools::CON.info("converting #{title}")
  
        ext = File.extname(outputFile).downcase
        ismp4 = false
        ismkv = false
        if ext.eql?(".mp4") or ext.eql?(".m4v")
          ismp4 = true
        elsif ext.eql?(".mkv")
          ismkv = true
        else
          raise "error unsupported extension #{ext}"
        end
  
        command="\"#{HANDBRAKE_CLI}\""
        command << " --input \"#{source.path()}\""
        command << " --output \"#{outputFile}\""
        command << " --chapters #{options.chapters}" if not options.chapters.nil?
        command << " --verbose" if options.verbose
  
        preset_arguments = nil
        if not options.preset.nil?
          preset_arguments = getPresets()[options.preset]
          if not preset_arguments.nil?
            cleaned_preset_arguments = preset_arguments.dup
            [
              "-E", "--aencoder",
              "-a", "--audio",
              "-R", "--arate",
              "-f", "--format",
              "-6", "--mixdown",
              "-B", "--ab",
              "-D", "--drc"
              ].each do |a|
              cleaned_preset_arguments.gsub!(/#{a} [^ ]+[ ]*/, "")
            end
            #puts cleaned_preset_arguments
            #puts preset_arguments
            # set preset arguments now and override some of them later
            command << " #{cleaned_preset_arguments}"
          end
        end
  
        if options.preset.nil?
          command << " --encoder x264"
          command << " --quality 20.0"
          command << " --decomb"
          command << " --detelecine"
          command << " --crop 0:0:0:0" if not options.enableAutocrop
          if not options.ipodCompatibility
            command << " --loose-anamorphic"
          end
          if ismp4 and options.ipodCompatibility
            command << " --ipod-atom"
            command << " --encopts level=30:bframes=0:cabac=0:weightp=0:8x8dct=0" if preset.nil?
          end
        end
        
        command << " --maxHeight #{options.maxHeight}" if options.maxHeight
        command << " --maxWidth #{options.maxWidth}" if options.maxWidth
        command << " --x264-profile #{options.x264profile}" if not options.x264profile.nil?
        command << " --x264-preset #{options.x264preset}" if not options.x264preset.nil?
        command << " --x264-tune #{options.x264tune}" if not options.x264tune.nil?
  
        # format
        if ismp4
          command << " --format mp4"
          command << " --optimize"
        elsif ismkv
          command << " --format mkv"
        end
  
        command << " --markers"
        
        if not options.preview.nil?
          p = options.preview.split("-",2)
          if p.size == 1
            start_at = "00:01:00"
            stop_at = Tools::TimeTool::secondsToTime(Tools::TimeTool::timeToSeconds(start_at) + 60)
          else
            start_at = p.first
            stop_at = Tools::TimeTool::secondsToTime(Tools::TimeTool::timeToSeconds(p.last) - Tools::TimeTool::timeToSeconds(start_at))
          end
          command << " --start-at duration:#{Tools::TimeTool::timeToSeconds(start_at)}"
          command << " --stop-at duration:#{Tools::TimeTool::timeToSeconds(stop_at)}"
        end
  
        # audio
        paudio = []
        paencoder = []
        parate = []
        pmixdown = []
        pab = []
        pdrc = []
        paname = []
        
        tracks.each do |t|
          mixdown_track = options.audioMixdown
          copy_track = options.audioCopy
          use_preset_settings = !options.preset.nil?
          mixdown = nil
  
          if mixdown_track
            mixdown = getMixdown(t, options.audioMixdownMappings, "dpl2")
            if mixdown.eql?("copy")
              mixdown = nil
              mixdown_track = false
              copy_track = true
            end
          end
          
          if use_preset_settings
            mixdown_track = false
            copy_track = false
          end
  
          Tools::CON.info("checking audio-track #{t}")
          if use_preset_settings
            value = preset_arguments.match(/(?:-a|--audio) ([^ ]+)/)[1]
            track_count = value.split(",").size
            paudio << ([t.pos] * track_count).join(",")
            value = preset_arguments.match(/(?:-E|--aencoder) ([^ ]+)/)[1]
            paencoder << value unless value.nil?
            value = preset_arguments.match(/(?:-R|--arate) ([^ ]+)/)[1]
            parate << value unless value.nil?
            value = preset_arguments.match(/(?:-6|--mixdown) ([^ ]+)/)[1]
            pmixdown << value unless value.nil?
            value = preset_arguments.match(/(?:-B|--ab) ([^ ]+)/)[1]
            pab << value unless value.nil?
            value = preset_arguments.match(/(?:-D|--drc) ([^ ]+)/)[1]
            pdrc << value unless value.nil?
            paname << (["#{t.descr(true)}"] * track_count).join("\",\"")
            Tools::CON.info("adding audio-track: #{t}")            
          end
          if copy_track
            # copy original track
            paudio << t.pos
            paencoder << "copy"
            parate << "auto"
            pmixdown << "auto"
            pab << "auto"
            pdrc << "0.0"
            paname << "#{t.descr}"
            Tools::CON.info("adding audio-track: #{t}")
          end
          if mixdown_track
            # add mixdown track
            paudio << t.pos
            if not options.audioMixdownEncoder.nil?
              paencoder << options.audioMixdownEncoder
            elsif ismp4
              paencoder << "faac"
            else
              paencoder << "lame"
            end
            parate << "auto"
            pmixdown << mixdown
            pab << options.audioMixdownBitrate
            pdrc << "0.0"
            paname << "#{t.descr(true)} (#{AUDIO_MIXDOWN_DESCR[mixdown] || mixdown})"
            Tools::CON.info("adding mixed down audio-track: #{t}")
          end
        end
        command << " --audio #{paudio.join(',')}"
        command << " --aencoder #{paencoder.join(',')}" unless paencoder.empty?
        command << " --arate #{parate.join(',')}" unless parate.empty?
        command << " --mixdown #{pmixdown.join(',')}" unless pmixdown.empty?
        command << " --ab #{pab.join(',')}" unless pab.empty?
        command << " --drc #{pdrc.join(',')}" unless pdrc.empty?
        command << " --aname \"#{paname.join('","')}\""
        if ismp4
          command << " --audio-fallback faac"
        else
          command << " --audio-fallback lame"
        end
  
        # subtitles
        psubtitles = subtitles.collect{ |s| s.pos }
        command << " --subtitle #{psubtitles.join(',')}" if not psubtitles.empty?()
  
        command << " --title #{title.pos}"
  
        # arguments to delegate...
        command << " #{options.xtra_args}" if not options.xtra_args.nil?

        if options.verbose
          command << " 2>&1"
        else
          command << " 2>#{Tools::OS::nullDevice()}"
        end
  
        Tools::CON::warn "converting title #{title.pos} #{title.duration} #{title.size} (blocks: #{title.blocks()})"
        if not tracks.empty?
          Tools::CON::warn "  audio-tracks"
          tracks.each do |t|
            Tools::CON::warn "    - track #{t.pos}: #{t.descr}"
          end
        end
        if not subtitles.empty?
          Tools::CON::warn "  subtitles"
          subtitles.each do |s|
            Tools::CON::warn "    - track #{s.pos}: #{s.descr}"
          end
        end
  
        Tools::CON.warn(command)
        if not options.debug and options.testdata.nil?
          parentDir = File.dirname(outputFile)
          FileUtils.mkdir_p(parentDir) unless File.directory?(parentDir)
          system command
          return_code = $?
          if File.exists?(outputFile)
            size = Tools::FileTool::size(outputFile)
            if return_code != 0
              Tools::CON.warn("Handbrake exited with return-code #{return_code} - removing file #{File.basename(outputFile)}")
              File.delete(outputFile)
              converted.delete(title.blocks())
            elsif size >= 0 and size < (1 * 1024 * 1024)
              Tools::CON.warn("file-size only #{Tools::FileTool::humanReadableSize(size)} - removing file #{File.basename(outputFile)}")
              File.delete(outputFile)
              converted.delete(title.blocks())
            else
              Tools::CON.warn("file #{outputFile} created (#{Tools::FileTool::humanReadableSize(size)})")
              created << outputFile
            end
          else
            Tools::CON.warn("file #{outputFile} not created")
          end
        end
        Tools::CON.warn("== done ===========================================================")
      end
      return created
    end
  end
  
  class Chapter
    attr_accessor :pos, :cells, :blocks, :duration
    def initialize(pos)
      @pos = pos.to_i
      @duration = nil
      @cells = nil
      @blocks = nil
    end
  
    def to_s
      "#{pos}. #{duration} (cells=#{cells}, blocks=#{blocks})"
    end
  end
  
  class Subtitle
    attr_accessor :pos, :descr, :comment, :lang
    def initialize(pos, descr, lang)
      @pos = pos.to_i
      @lang = lang
      @descr = descr
      @comment = nil
    end
  
    def commentary?()
      return true if @descr.downcase().include?("commentary")
      return false
    end
  
    def to_s
      "#{pos}. #{descr} (lang=#{lang}, comment=#{comment}, commentary=#{commentary?()})"
    end
  end
  
  class AudioTrack
    attr_accessor :pos, :descr, :codec, :comment, :channels, :lang, :rate, :bitrate
    def initialize(pos, descr)
      @pos = pos.to_i
      @descr = descr
      @codec = nil
      @comment = nil
      @channels = nil
      @lang = nil
      @rate = nil
      @bitrate = nil
    end
    
    def descr(cleaned = false)
      return @descr unless cleaned
      d = @descr.dup
      d.gsub!(/[(]?#{codec}[)]?/, "")
      d.gsub!(/[(]?#{channels}[)]?/, "")
      d.strip!
      return d
    end
  
    def commentary?()
      return true if @descr.downcase().include?("commentary")
      return false
    end
  
    def to_s
      "#{pos}. #{descr} (codec=#{codec}, channels=#{channels}, lang=#{lang}, comment=#{comment}, rate=#{rate}, bitrate=#{bitrate}, commentary=#{commentary?()})"
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
      @size = nil
      @fps = nil
      @duration = nil
      @mainFeature = false
    end
  
    def to_s
      "title #{"%02d" % pos}: #{duration}, #{size}, #{fps} fps, main-feature: #{mainFeature()}, blocks: #{blocks}, chapters: #{chapters.length}, audio-tracks: #{audioTracks.collect{|t| t.lang}.join(",")}, subtitles: #{subtitles.collect{|s| s.lang}.join(",")}"
    end
  end
  
  class MovieSource
    attr_accessor :title, :title_alt, :serial, :titles, :path
    def initialize(path)
      @titles = []
      @path = path
      @title = nil
      @title_alt = nil
      @serial = nil
    end
  
    def name(use_alt = false)
      return @title_alt if usable?(@title_alt) and use_alt
      return @title if usable?(@title)
      if File.directory?(path)
        name = File.basename(path())
        name = File.basename(File.dirname(path)) if ["VIDEO_TS", "AUDIO_TS"].include?(name)
      else
        name = File.basename(path(), ".*")
      end
      return name if usable?(name)
      return "unknown"
    end
  
    def usable?(str)
      return false if str.nil?
      return false if str.strip.empty?
      return false if str.strip.eql? "unknown"
      return true
    end
  
    def info
      s = "#{self}"
      titles().each do |t|
        s << "\n#{t}"
        s << "\n  audio-tracks:"
        t.audioTracks().each do |e|
          s << "\n    #{e}"
        end
        s << "\n  subtitles:"
        t.subtitles().each do |e|
          s << "\n    #{e}"
        end
        s << "\n  chapters:"
        t.chapters().each do |c|
          s << "\n    #{c}"
        end
      end
      s
    end
  
    def to_s
      "#{path} (title=#{title}, title_alt=#{title_alt}, serial=#{serial}, name=#{name()})"
    end
  end
  
  class ValueMatcher
    attr_accessor :allowed, :onlyFirstPerAllowedValue
    def initialize(allowed)
      @allowed = allowed
      @onlyFirstPerAllowedValue = false
    end
    
    def check(obj)
      return true
    end
  
    def value(obj)
      raise "method not implemented"
    end
  
    def matches(obj)
      m = (allowed().nil? or allowed().include?(value(obj)))
      m = false if not check(obj)
      Tools::CON.debug("#{self.class().name()}: #{value(obj).inspect} is allowed (#{allowed.inspect()})? -> #{m}")
      return m
    end
  
    def filter(list)
      return list if allowed().nil?
  
      filtered = []
      stack = []
      allowed().each do |a|
        list.each do |e|
          next if not matches(e)
          v = value(e)
          next if @onlyFirstPerAllowedValue and stack.include?(v)
          if (v == a or v.eql? a)
            stack.push v
            filtered.push e
          end
        end
      end
      return filtered
    end
  
    def to_s
      "#{@allowed}"
    end
  end
  
  class PosMatcher < ValueMatcher
    def value(obj)
      return obj.pos
    end
  end
  
  class LangMatcher < ValueMatcher
    attr_accessor :skipCommentaries
    skipCommentaries = false
  
    def value(obj)
      obj.lang
    end
  
    def check(obj)
      return false if @skipCommentaries and obj.commentary?
      return true
    end
  end
end