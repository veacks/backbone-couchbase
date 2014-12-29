"use strict"
module.exports = coffee = (grunt) ->

  # Load task
  grunt.loadNpmTasks "grunt-contrib-coffee"

  {
    'index.js': ['src/**/*.coffee']
  }