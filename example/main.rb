#!/usr/bin/env ruby

# Example Ruby utility
# Replace this with your actual application code

require 'thor'

class MyUtility < Thor
  desc "hello NAME", "Say hello to NAME"
  def hello(name)
    puts "Hello #{name}! This is running in an isolated Ruby environment."
    puts "Ruby version: #{RUBY_VERSION}"
    puts "GEM_HOME: #{ENV['GEM_HOME']}"
  end

  desc "version", "Show version info"
  def version
    puts "My Ruby Utility v0.1.0"
    puts "Ruby: #{RUBY_VERSION}"
  end
end

MyUtility.start(ARGV)
