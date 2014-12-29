Q = require "q"
uuid = require "node-uuid"
couchbase = require "couchbase"
ViewQuery = couchbase.ViewQuery
_ = require "underscore"


module.exports = (bucket, sep = "::") ->
  _keyFormat = (url) ->
    url = decodeURIComponent url
    url = url.replace /^(\/)/, ''
    url = url.replace  /\//g, sep

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
          options.error err
        def.reject err
        if options.trace
          console.log "  - err:"
          console.log err
        return

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

        bucket.replace  _keyFormat(model.url()), dbModel, (err, result) ->
          if err?
            couchbase_callback err, result
            return false
          
          bucket.get _keyFormat(model.url()), couchbase_callback

    # Delete an object
    else if method is "delete"
      bucket.remove  _keyFormat(model.url()), couchbase_callback
    else
      couchbase_callback { code: 500, message: "#{method}: Wrong or empty method for Backbone-Couchbase-Sync" }

          
    model.trigger 'request', model, null, options
    return def.promise