Q = require "q"
uuid = require "node-uuid"
couchbase = require "couchbase"
ViewQuery = couchbase.ViewQuery
_ = require "underscore"

###
# Create a Couchbase Sync Method for Backbone Models and Collections
# @param {object} [options={}] - Options for the creation of the sync method
# @option {object} bucket - Bucket object for the synchronisation
# @option {object} connection - Cluster address, bucket name and password
# @option {string} [sep="::"] - Replace "/" by separator, if false the url wont be formated
# @option {boolean} [httpError=false] - Format couchbase error to http friendly status
# @return {function} Backbone Couchbase Sync function
###
module.exports = (options = {}) ->
  # Check if bucket or connections are present
  unless options.bucket? or options.connection?
    throw new Error "Bucket or Connection object is required to generate sync method"

  # Assign bucket injected bucket
  if options.bucket?
    bucket = options.bucket

  # Create bucket with conf datas
  else if options.connection?
    # Retrun an error if cluster or bucket parameters are missing
    unless options.connection.cluster? and options.connection.bucket?
      throw new Error "Connection bucket and cluster are required"

    cluster = new couchbase.Cluster options.connection.cluster
    if options.connection.password?
      bucket = cluster.openBucket options.connection.bucket, options.connection.password
    else
      bucket = cluster.openBucket options.connection.bucket

  # Error formating
  httpError = options.httpError || true
  # Separator
  sep = options.sep || "::"
  # Id generator
  idGen = options.idGen || uuid
  
  ###
  # Format the document key
  # @private
  ###
  _keyFormat = (url) ->
    # If sep is false, dont format the url
    unless sep
      return url
    url = decodeURIComponent url
    url = url.replace /^(\/)/, ''
    url = url.replace  /\//g, sep

  ###
  # Format couchbase error to http friendly
  # @private
  ###
  _couchbaseErrorFormat = (error) ->
    # if error is false, dont format error
    unless httpError
      return error
    
    switch error.toString()
      when "Error: key does not exist"
        return {
          status: 404
          message: error
        }
      when "Error: key already exists"
        return {
          status: 409
          message: error
        }
      else
        return {
          status: 500
          message: error
        }

  ###
  # Generate the Backbone Sync Method
  # @param {string} method - CRUD command
  # @param {object} model - Backbone Model or Collection object
  # @param {object} options - Sync options
  # @option {callback~Error} error - Callback error
  # @option {callback~Success} success - Callback success 
  # @option {boolean} trace - Trace Couchbase process
  # @option {boolean} create - Force creation with a specific key 
  # @return promise
  ###
  return (method, model, options) ->
    def = Q.defer()

    couchbase_callback = (err, result) ->
      # Trace insertion
      if options.trace
        console.log "-----"
        console.log "Backbone Couchbase:"
        console.log "  - method:"
        console.log method
        console.log "  - id:"
        console.log _keyFormat(model.url())
        console.log options

      if err?
        if options? and options.error?
          options.error _couchbaseErrorFormat err
        def.reject _couchbaseErrorFormat err
        if options.trace
          console.log "  - err:"
          console.log err
        return false

      # If collection result
      if _.isArray result
        response = []
        response.push model.value for model in result
      # Else if model
      else
        response = result.value

      if options? and options.success?
        options.success response
      def.resolve response

      if options.trace
        console.log "  - response:"
        console.log response
        console.log "-----"

    # Create a new object
    if method is "create" or (options.create? and options.create)
      model.set model.idAttribute, uuid.v4() if model.isNew()
      bucket.insert _keyFormat(model.url()), model.toJSON(), (err, result) ->
        if err?
          couchbase_callback err, result
          return false

        bucket.get _keyFormat(model.url()), couchbase_callback

    # Update an existing object
    else if method is "update" and (not options.create? or not options.create)
      bucket.replace _keyFormat(model.url()), model.toJSON(), (err, result) ->
        if err?
          couchbase_callback err, result
          return false

        bucket.get _keyFormat(model.url()), couchbase_callback

    # Read an object
    else if method is "read"
      # Read collection
      if model.models?
        query = ViewQuery.from model.url, options.viewName || model.defaultView
        query.custom options.custom if options.custom?
        bucket.query query, couchbase_callback
      # Read model
      else
        bucket.get _keyFormat(model.url()), couchbase_callback

    # Patch an object (edit only partialy)
    else if method is "patch"
      bucket.get _keyFormat(model.url()), (err, result) ->
        if err?
          couchbase_callback err, result
          return

        dbModel = result.value

        _.extend dbModel, model.toJSON()

        bucket.replace _keyFormat(model.url()), dbModel, (err, result) ->
          if err?
            couchbase_callback err, result
            return false
          
          bucket.get _keyFormat(model.url()), couchbase_callback

    # Delete an object
    else if method is "delete"
      bucket.remove  _keyFormat(model.url()), couchbase_callback
    else
      couchbase_callback { code: 500, message: "#{method}: Wrong or empty method for Backbone-Couchbase-Sync" }

          
    model.trigger 'request', model, def.promise, options
    return def.promise
