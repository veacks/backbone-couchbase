(function() {
  var Backbone, N1qlIndexesChecker, N1qlQuery, Q, ViewQuery, async, couchbase, uuid, _, _originalCollectionFetch;

  Q = require("q");

  uuid = require("node-uuid");

  couchbase = require("couchbase");

  ViewQuery = couchbase.ViewQuery;

  N1qlQuery = couchbase.N1qlQuery;

  _ = require("underscore");

  async = require("async");

  Backbone = require("backbone");

  N1qlIndexesChecker = require("./N1qlIndexesChecker");


  /*
   * Set up the join functionally at the Backbone Collection level
   * @param {object} [options={}] - Options for the fetch method
   */

  _originalCollectionFetch = Backbone.Collection.prototype.fetch;

  Backbone.Collection.prototype.fetch = function(options) {
    var success;
    options = options ? _.clone(options) : {};
    if ((options.join != null) && options.join === true || typeof options.join === "function") {
      success = options.success;
      options.success = (function(_this) {
        return function(resp) {
          var tasks;
          tasks = [];
          _this.each(function(model) {
            return tasks.push(function(aCb) {
              return model.fetch({
                join: options.join === true && (model.join != null) ? true : typeof options.join === "function" ? options.join : void 0,
                success: function() {
                  return aCb();
                },
                error: function(model, error) {
                  return aCb(error);
                }
              });
            });
          });
          return async.parallel(tasks, function(error) {
            if (success != null) {
              return success.call(options.context, _this, resp, options);
            }
          });
        };
      })(this);
    }
    return _originalCollectionFetch.apply(this, [options]);
  };


  /*
   * Create a Couchbase Sync Method for Backbone Models and Collections
   * @param {object} [options={}] - Options for the creation of the sync method
   * @option {object} bucket - Bucket object for the synchronisation
   * @option {object} connection - Cluster address, bucket name and password
   * @option {string} [sep="::"] - Replace "/" by separator, if false the url wont be formated
   * @option {boolean} [httpError=false] - Format couchbase error to http friendly status
   * @return {function} Backbone Couchbase Sync function
   */

  module.exports = function(options) {
    var bucket, cluster, connectionCb, def, httpError, idGen, sep, _couchbaseErrorFormat, _keyFormat, _keysFormat, _syncMethod, _viewsChecker;
    if (options == null) {
      options = {};
    }

    /*
     * Format the document keys
     * @private
     */
    _keysFormat = function(url, ids) {
      var id, uList, _i, _len;
      uList = [];
      for (_i = 0, _len = ids.length; _i < _len; _i++) {
        id = ids[_i];
        uList.push(_keyFormat(url + "/" + id));
      }
      return uList;
    };

    /*
     * Format the document key
     * @private
     */
    _keyFormat = function(url) {
      url = decodeURIComponent(url);
      url = url.replace(/^(\/)/, '');
      return url = url.replace(/\//g, sep);
    };

    /*
     * Format couchbase error to http friendly
     * @private
     */
    _couchbaseErrorFormat = function(error, result) {
      if (!httpError) {
        return error;
      }
      switch (error.code) {
        case 13:
          return {
            status: 404,
            message: error.toString()
          };
        case 12:
          return {
            status: 409,
            message: error.toString()
          };
        default:
          return {
            status: 500,
            message: result || error
          };
      }
    };

    /*
     * Generate the Backbone Sync Method
     * @param {string} method - CRUD command
     * @param {object} model - Backbone Model or Collection object
     * @param {object} options - Sync options
     * @option {callback~Error} error - Callback error
     * @option {callback~Success} success - Callback success 
     * @option {boolean} trace - Trace Couchbase process
     * @option {boolean} create - Force creation with a specific key 
     * @return promise
     */
    _syncMethod = function(method, model, options) {
      var couchbase_callback, def, designDocuement, formatedIds, query, reducedView, viewName, _ensureIndexes, _error, _success;
      def = Q.defer();

      /*
       * Send the success response
       * @private
       */
      _success = function(response) {
        if (options.success != null) {
          options.success(response);
        }
        return def.resolve(response);
      };

      /*
       * Send the error response
       * @private
       */
      _error = function(err) {
        if ((options != null) && (options.error != null)) {
          options.error(_couchbaseErrorFormat(err));
        }
        return def.reject(_couchbaseErrorFormat(err));
      };

      /*
       * N1ql indexes
       */
      _;
      _ensureIndexes = function(indexes) {};
      reducedView = false;

      /*
       * Callback to get the updated datas
       * @private
       */
      couchbase_callback = function(err, result) {
        var id, item, response, _i, _j, _len, _len1;
        def.promise.cbError = err;
        def.promise.cbResult = result;
        if (options.trace) {
          console.log("  - method:");
          console.log(method);
          console.log("  - id:");
          switch (typeof model.url) {
            case "function":
              console.log(_keyFormat(model.url()));
              break;
            case "string":
              console.log(model.url);
          }
          console.log(options);
          console.log("  - result:");
          console.log(result);
        }
        if ((err != null) && (err !== 0 || (err.length != null) && err.length > 0)) {
          if (options.ids == null) {
            _error(err);
          } else {
            _error(err, result);
          }
          if (options.trace) {
            console.log("  - err:");
            console.log(err);
          }
          return;
        }
        if (_.isArray(result)) {
          if (reducedView && !options.group) {
            response = result[0] != null ? result[0].value : 0;
          } else if (reducedView && options.group) {
            response = [];
            for (_i = 0, _len = result.length; _i < _len; _i++) {
              item = result[_i];
              response.push(item.value[0] || item.value);
            }
          } else {
            response = [];
            for (_j = 0, _len1 = result.length; _j < _len1; _j++) {
              item = result[_j];
              response.push(item.value);
            }
          }
        } else if ((options.ids != null) || (option.docIds != null)) {
          response = [];
          for (id in result) {
            item = result[id];
            response.push(item.value);
          }
        } else {
          response = result.value;
        }
        if (options.join === true && (model.join != null)) {
          model.join(response, function(err, joinedDatas) {
            if (err != null) {
              return _error(err);
            } else {
              return _success(joinedDatas);
            }
          });
          return;
        } else if (typeof options.join === "function") {
          options.join(model, response, function(err, joinedDatas) {
            if (err != null) {
              return _error(err);
            } else {
              return _success(joinedDatas);
            }
          });
          return;
        }
        _success(response);
        if (options.trace) {
          console.log("  - response:");
          console.log(response);
          return console.log("-----");
        }
      };
      if (options.trace) {
        console.log("-----");
        console.log("Backbone Couchbase:");
        console.log(" - method:");
        console.log(method);
      }
      if (method === "create" || ((options.create != null) && options.create)) {
        if (model.isNew()) {
          model.set(model.idAttribute, uuid.v4());
        }
        bucket.insert(_keyFormat(model.url()), model.toJSON(), function(err, result) {
          if (err != null) {
            couchbase_callback(err, result);
            return false;
          }
          return bucket.get(_keyFormat(model.url()), couchbase_callback);
        });
      } else if (method === "update" && ((options.create == null) || !options.create)) {
        bucket.replace(_keyFormat(model.url()), model.toJSON(), function(err, result) {
          if (err != null) {
            couchbase_callback(err, result);
            return false;
          }
          return bucket.get(_keyFormat(model.url()), couchbase_callback);
        });
      } else if (method === "read") {
        if ((model.models != null) && (options.ids != null)) {
          if (typeof options.ids === "string") {
            options.ids = [options.ids];
          }
          if (!_.isArray(options.ids)) {
            _error(new Error("options.ids must be a String or an Array!"));
          } else {
            formatedIds = _.map(options.ids, function(id) {
              var tempModel;
              if (model.model != null) {
                tempModel = new model.model();
                if (_.isObject(id)) {
                  tempModel.set(id);
                } else {
                  tempModel.set(tempModel.idAttribute, id);
                }
                return _keyFormat(tempModel.url());
              }
              if (_.isFunction(model.url)) {
                return _keyFormat("" + (model.url()) + "/" + id);
              }
              return _keyFormat("" + model.url + "/" + id);
            });
            bucket.getMulti(formatedIds, couchbase_callback);
          }
        } else if ((model.models != null) && (options.docIds != null)) {
          bucket.getMulti(options.docIds, couchbase_callback);
        } else if (model.type === "designDocument") {
          designDocuement = model.designDocument || model.url.split("/")[0];
          viewName = model.viewName || model.url.split("/")[1];
          query = ViewQuery.from(designDocuement, viewName);
          if (options.custom != null) {
            query.custom(options.custom);
          }
          if (options.full_set != null) {
            query.full_set(options.full_set);
          }
          if (options.group != null) {
            query.group(options.group);
          }
          if (options.group_level != null) {
            query.group_level(options.group_level);
          }
          if (options.id_range != null) {
            query.id_range(options.id_range.start, options.id_range.end);
          }
          if (options.include_docs != null) {
            query.include_docs(options.include_docs);
          }
          if (options.key != null) {
            query.key(options.key);
          }
          if (options.keys != null) {
            query.keys(options.keys);
          }
          if (options.limit != null) {
            query.limit(options.limit);
          }
          if (options.on_error != null) {
            query.on_error(options.on_error);
          }
          if (options.range != null) {
            query.range(options.range.start, options.range.end, options.inclusiveEnd);
          }
          if (options.order != null) {
            query.order(options.order);
          }
          if (((model.models == null) && (options.reduce == null)) || options.reduce) {
            reducedView = true;
            query.reduce(true);
          } else {
            query.reduce(false);
          }
          if (options.skip != null) {
            query.skip(skip);
          }
          if (options.stale != null) {
            query.stale(options.stale);
          }
          bucket.query(query, couchbase_callback);
        } else if (model.type === "N1ql") {
          N1qlIndexesChecker(bucket, model.indexes || [], function(err) {
            query = N1qlQuery.fromString(model.url());
            if (options.params != null) {
              return bucket.query(query, options.params, couchbase_callback);
            } else {
              return bucket.query(query, couchbase_callback);
            }
          });
        } else {
          bucket.get(_keyFormat(model.url()), couchbase_callback);
        }
      } else if (method === "patch") {
        bucket.get(_keyFormat(model.url()), function(err, result) {
          var dbModel;
          if (err != null) {
            couchbase_callback(err, result);
            return;
          }
          dbModel = result.value;
          _.extend(dbModel, model.toJSON());
          return bucket.replace(_keyFormat(model.url()), dbModel, function(err, result) {
            if (err != null) {
              couchbase_callback(err, result);
              return false;
            }
            return bucket.get(_keyFormat(model.url()), couchbase_callback);
          });
        });
      } else if (method === "delete") {
        bucket.remove(_keyFormat(model.url()), couchbase_callback);
      } else {
        couchbase_callback({
          code: 500,
          message: "" + method + ": Wrong or empty method for Backbone-Couchbase-Sync"
        });
      }
      model.trigger('request', model, def.promise, options);
      return def.promise;
    };

    /*
     * Set up and check the bucket connection
     */
    def = Q.defer();
    if (!((options.bucket != null) || (options.connection != null))) {
      throw new Error("Bucket or Connection object is required to generate sync method");
    }
    _viewsChecker = function() {
      var checkDesignDoc, dbm;
      dbm = bucket.manager();
      if (options.designDocuments != null) {
        checkDesignDoc = function(designDocName, callback) {
          return dbm.getDesignDocument(designDocName, function(err, serverDesignDoc) {
            if (err != null) {
              if (err.message === "missing" || err.message === "not_found" || err.message === "deleted") {
                dbm.insertDesignDocument(designDocName, options.designDocuments[designDocName], function(err) {
                  if (err != null) {
                    return callback(err);
                  } else {
                    return callback();
                  }
                });
              } else {
                callback(err);
              }
              return;
            }
            if (!_.isEqual(serverDesignDoc, options.designDocuments[designDocName])) {
              dbm.upsertDesignDocument(designDocName, options.designDocuments[designDocName], function(err) {
                if (err != null) {
                  return callback(err);
                } else {
                  return callback();
                }
              });
              return;
            }
            return callback();
          });
        };
        async.map(Object.keys(options.designDocuments), checkDesignDoc, function(err) {
          if (err != null) {
            def.reject(err);
            return;
          }
          return def.resolve(_syncMethod);
        });
        return;
      }
      return def.resolve(_syncMethod);
    };
    if (options.bucket != null) {
      bucket = options.bucket;
      _viewsChecker();
    } else if (options.connection != null) {
      if (!((options.connection.cluster != null) && (options.connection.bucket != null))) {
        throw new Error("Connection bucket and cluster are required");
      }
      cluster = new couchbase.Cluster(options.connection.cluster);

      /*
       * Connection callback
       */
      connectionCb = function(err) {
        if (err != null) {
          def.reject(err);
          return;
        }
        return _viewsChecker();
      };
      if (options.connection.password != null) {
        bucket = cluster.openBucket(options.connection.bucket, options.connection.password, connectionCb);
      } else {
        bucket = cluster.openBucket(options.connection.bucket, connectionCb);
      }
    }
    httpError = options.httpError || true;
    sep = options.sep || "::";
    idGen = options.idGen || uuid;
    return def.promise;
  };

}).call(this);
