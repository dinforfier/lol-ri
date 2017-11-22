# This util parses and stores scrapped LoL observer binary data
# Usage: ruby parse.rb <GAME_ID> <KEY> <DATA_SOURCE_DIR>

require 'csv'
require 'openssl'
require 'base64'
require 'zlib'
require 'json'
require 'fileutils'

GAME_ID=ARGV[0]
KEY=ARGV[1]
DATA_SOURCE_DIR = ARGV[2]
OUTPUT_DIR = './data'

# GAME_ID = '3410907089'
# KEY = 'mPwXCfy2+9FcnhOU2q8YXvamM1weptEH'
# DATA_SOURCE_DIR='../lol-ob-scrapper/data/EUW1/3410907089'

if !GAME_ID || !KEY || !DATA_SOURCE_DIR 
  puts "Usage ruby parse.rb <GAME_ID> <KEY> <DATA_SOURCE_DIR>"
  exit
end

def decrypt(key, data)
  c = OpenSSL::Cipher.new('bf-ecb')
  c.decrypt
  c.key_len = key.bytesize
  c.key = key
  c.update(data) + c.final
end

def format_string_hex(str)
  str.bytes.each_slice(4).map { |arr| arr.map{ |o| o.to_s(16) }.join('-') }.join(' ')
end

def format_string_ascii(str)
  str.bytes.map {|o| o > 0x2e && o < 0x7f ? o : 0x2e }.pack('c*')
end


class BlockFlag
  attr_reader :value

  def initialize(value)
    @value = value
  end

  def one_byte_length?
    has_flag?(FLAG_ONE_BYTE_CONTENT_LENGTH)
  end

  def one_byte_param?
    has_flag?(FLAG_ONE_BYTE_PARAM)
  end

  def same_type?
    has_flag?(FLAG_SAME_TYPE)
  end

  def relative_time?
    has_flag?(FLAG_RELATIVE_TIME)
  end

  def to_i
    @value
  end

  private

  FLAG_ONE_BYTE_CONTENT_LENGTH = 1 << 0
  FLAG_ONE_BYTE_PARAM = 1 << 1
  FLAG_SAME_TYPE = 1 << 2
  FLAG_RELATIVE_TIME = 1 << 3

  def has_flag?(f)
    (@value & f) != 0
  end

end

class Block < Struct.new(:flags, :channel, :timestamp, :type, :params, :content)
  def self.empty
    Struct.new(BlockFlag.new(0), 0, 0, 0, "", "")
  end
end

class Parser

  attr_accessor :blocks

  def initialize(data)
    @stream = StringIO.new(data)
    @blocks = []
  end

  def parse!
    @blocks while parse_block!
  end

  private

  def parse_block!
    begin
      header = @stream.readbyte
    rescue EOFError
      return nil
    end

    flags = BlockFlag.new(header >> 4)
    channel = header & 0xf
    timestamp = if flags.relative_time?
                  prev_ts = @blocks.last.timestamp
                  offset = @stream.read(1).unpack('C').first
                  prev_ts + 0.001 * offset
                else
                  @stream.read(4).unpack('f').first
                end

    content_length = if flags.one_byte_length?
                       @stream.read(1).unpack('C').first
                     else
                       @stream.read(4).unpack('L').first
                     end

    type = if flags.same_type?
             @blocks.last.type
           else
             @stream.read(2).unpack('S').first
           end

    params = if flags.one_byte_param?
               @stream.read(1)
             else
               @stream.read(4)
             end

    content = @stream.read(content_length)

    block = Block.new(flags, channel, timestamp, type, params, content)

    @blocks << block

    block
  end
end

encrypted_key = Base64.decode64(KEY)

Dir[File.join(DATA_SOURCE_DIR, '*.data')].each do |path|
  puts "Parsing #{path}"
  encrypted_data = File.open(path).read
  key = decrypt(GAME_ID, encrypted_key)
  gzipped_data = decrypt(key, encrypted_data)
  gz = Zlib::GzipReader.new(StringIO.new(gzipped_data))
  data = gz.read
  gz.close

  parser = Parser.new(data)
  parser.parse!

  generated_csv = CSV.generate do |csv|
    parser.blocks.each do |block|
      csv << [block.timestamp, block.flags.value, block.channel, block.type, format_string_hex(block.params), format_string_hex(block.content), format_string_ascii(block.content)]
    end
  end

  destination_dir = File.join(OUTPUT_DIR, GAME_ID)
  destination_file = File.basename(path)

  FileUtils.mkdir_p(destination_dir)
  File.open(File.join(destination_dir, destination_file), 'w') do |file|
    file << generated_csv
  end
end
