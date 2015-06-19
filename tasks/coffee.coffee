"use strict"
module.exports = coffee = (grunt) ->

  # Load task
  grunt.loadNpmTasks "grunt-contrib-coffee"

  {
    build:
      expand: true
      flatten: true
      cwd: "src/"
      src: "*.coffee"
      dest: "build/"
      ext: ".js"
  }