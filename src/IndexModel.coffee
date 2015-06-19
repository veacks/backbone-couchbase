###
# @class IndexModel
# @description Help to manage dee equality for indexes
###
module.exports = class IndexModel
  ###
  # @member {string} name - name of the index
  ###
  name: String

  ###
  # @member {boolean}  is_primary - is a primary index
  ###
  is_primary: Boolean
  
  ###
  # @member {string} using - Type of indexing (GSI or VIEW)
  ###
  using: String
  
  ###
  # @member {array} index_key - Keys to index
  ###
  index_key: Array

  ###
  # @constructor
  # @param {string} name - name of the index
  # @param {boolean}  is_primary - is a primary index
  # @param {string} using - Type of indexing (GSI or VIEW)
  # @param {array} index_key - Keys to index
  ###
  constructor: (name, is_primary, using, index_key) ->
    @name = name
    @is_primary = is_primary || true
    @using = using || "GSI"
    @index_key = index_key || []