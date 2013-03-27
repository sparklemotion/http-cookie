require 'http/cookie_jar'
require 'sqlite3'

class HTTP::CookieJar
  class MozillaStore < AbstractStore
    SCHEMA_VERSION = 5

    def default_options
      {
        :gc_threshold => HTTP::Cookie::MAX_COOKIES_TOTAL / 20,
        :app_id => 0,
        :in_browser_element => false,
      }
    end

    ALL_COLUMNS = %w[
      baseDomain
      appId inBrowserElement
      name value
      host path
      expiry creationTime lastAccessed
      isSecure isHttpOnly
    ]
    UK_COLUMNS = %w[
      name host path
      appId inBrowserElement
    ]

    def initialize(options = nil)
      super

      @filename = options[:filename] or raise ArgumentError, ':filename option is missing'

      @db = SQLite3::Database.new(@filename)
      @db.results_as_hash = true

      upgrade_database

      @gc_index = 0
    end

    def schema_version
      @schema_version ||= @db.execute("PRAGMA user_version").first[0]
    rescue SQLite3::SQLException
      @logger.warn "couldn't get schema version!" if @logger
      return nil
    end

    protected

    def schema_version=(version)
      @db.execute("PRAGMA user_version = %d" % version)
      @schema_version = version
    end

    def create_table
      self.schema_version = SCHEMA_VERSION
      @db.execute("DROP TABLE IF EXISTS moz_cookies")
      @db.execute(<<-'SQL')
                   CREATE TABLE moz_cookies (
                     id INTEGER PRIMARY KEY,
                     baseDomain TEXT,
                     appId INTEGER DEFAULT 0,
                     inBrowserElement INTEGER DEFAULT 0,
                     name TEXT,
                     value TEXT,
                     host TEXT,
                     path TEXT,
                     expiry INTEGER,
                     lastAccessed INTEGER,
                     creationTime INTEGER,
                     isSecure INTEGER,
                     isHttpOnly INTEGER,
                     CONSTRAINT moz_uniqueid UNIQUE (name, host, path, appId, inBrowserElement)
                   )
      SQL
      @db.execute(<<-'SQL')
                   CREATE INDEX moz_basedomain
                     ON moz_cookies (baseDomain,
                                     appId,
                                     inBrowserElement);
      SQL
    end

    def upgrade_database
      loop {
        case schema_version
        when nil, 0
          self.schema_version = SCHEMA_VERSION
          break
        when 1
          @db.execute("ALTER TABLE moz_cookies ADD lastAccessed INTEGER")
          self.schema_version += 1
        when 2
          @db.execute("ALTER TABLE moz_cookies ADD baseDomain TEXT")

          st_update = @db.prepare("UPDATE moz_cookies SET baseDomain = :baseDomain WHERE id = :id")

          @db.execute("SELECT id, host FROM moz_cookies") { |row|
            domain = DomainName.new(row[:host]).domain
            st_update.execute(:baseDomain => domain, :id => row[:id])
          }

          @db.execute("CREATE INDEX moz_basedomain ON moz_cookies (baseDomain)")
          self.schema_version += 1
        when 3
          st_delete = @db.prepare("DELETE FROM moz_cookies WHERE id = :id")

          prev_row  = nil
          @db.execute(<<-'SQL') { |row|
                       SELECT id, name, host, path FROM moz_cookies
                         ORDER BY name ASC, host ASC, path ASC, expiry ASC
          SQL
            if %w[name host path].all? { |col| row[col] == prev_row[col] }
              st_delete.execute(prev_row['id'])
            end
            prev_row = row
          }

          @db.execute("ALTER TABLE moz_cookies ADD creationTime INTEGER")
          @db.execute("UPDATE moz_cookies SET creationTime = (SELECT id WHERE id = moz_cookies.id)")
          @db.execute("CREATE UNIQUE INDEX moz_uniqueid ON moz_cookies (name, host, path)")
          self.schema_version += 1
        when 4
          @db.execute("ALTER TABLE moz_cookies RENAME TO moz_cookies_old")
          @db.execute("DROP INDEX moz_basedomain")
          create_table
          @db.execute(<<-'SQL')
                       INSERT INTO moz_cookies
                         (baseDomain, appId, inBrowserElement, name, value, host, path, expiry,
                          lastAccessed, creationTime, isSecure, isHttpOnly)
                         SELECT baseDomain, 0, 0, name, value, host, path, expiry,
                                lastAccessed, creationTime, isSecure, isHttpOnly
                           FROM moz_cookies_old
          SQL
          @db.execute("DROP TABLE moz_cookies_old")
          @logger.info("Upgraded database to schema version %d" % schema_version) if @logger
        else
          break
        end
      }

      begin
        @db.execute("SELECT %s from moz_cookies limit 1" % ALL_COLUMNS.join(', '))
      rescue SQLite3::SQLException
        create_table
      end
    end

    public

    def add(cookie)
      @st_add ||=
        @db.prepare('INSERT OR REPLACE INTO moz_cookies (%s) VALUES (%s)' % [
          ALL_COLUMNS.join(', '),
          ALL_COLUMNS.map { |col| ":#{col}" }.join(', ')
        ])

      @st_add.execute({
          :baseDomain => cookie.domain_name.domain,
          :appId => @app_id,
          :inBrowserElement => @in_browser_element ? 1 : 0,
          :name => cookie.name, :value => cookie.value,
          :host => cookie.dot_domain,
          :path => cookie.path,
          :expiry => cookie.expires_at.to_i,
          :creationTime => cookie.created_at.to_i,
          :lastAccessed => cookie.accessed_at.to_i,
          :isSecure => cookie.secure? ? 1 : 0,
          :isHttpOnly => cookie.httponly? ? 1 : 0,
        })
      cleanup if (@gc_index += 1) >= @gc_threshold

      self
    end

    def each(uri = nil)
      now = Time.now
      if uri
        @st_cookies_for_domain ||=
          @db.prepare(<<-'SQL')
                       SELECT * FROM moz_cookies
                         WHERE baseDomain = :baseDomain AND
                               appId = :appId AND
                               inBrowserElement = :inBrowserElement AND
                               expiry >= :expiry
                      SQL

        @st_update_lastaccessed ||=
            @db.prepare("UPDATE moz_cookies SET lastAccessed = :lastAccessed where id = :id")

        thost = DomainName.new(uri.host)
        tpath = HTTP::Cookie.normalize_path(uri.path)

        @st_cookies_for_domain.execute({
            :baseDomain => thost.domain_name.domain,
            :appId => @app_id,
            :inBrowserElement => @in_browser_element ? 1 : 0,
            :expiry => now.to_i,
          }).each { |row|
          if secure = row['isSecure'] != 0
            next unless URI::HTTPS === uri
          end

          cookie = HTTP::Cookie.new({}.tap { |attrs|
              attrs[:name]        = row['name']
              attrs[:value]       = row['value']
              attrs[:domain]      = row['host']
              attrs[:path]        = row['path']
              attrs[:expires_at]  = Time.at(row['expiry'])
              attrs[:accessed_at] = Time.at(row['lastAccessed'])
              attrs[:created_at]  = Time.at(row['creationTime'])
              attrs[:secure]      = secure
              attrs[:httponly]    = row['isHttpOnly'] != 0
            })

          if cookie.valid_for_uri?(uri)
            cookie.accessed_at = now
            @st_update_lastaccessed.execute({
                'lastAccessed' => now.to_i,
                'id' => row['id'],
              })
            yield cookie
          end
        }
      else
        @st_all_cookies ||=
          @db.prepare(<<-'SQL')
                       SELECT * FROM moz_cookies
                         WHERE appId = :appId AND
                               inBrowserElement = :inBrowserElement AND
                               expiry >= :expiry
                      SQL

        @st_all_cookies.execute({
            :appId => @app_id,
            :inBrowserElement => @in_browser_element ? 1 : 0,
            :expiry => now.to_i,
          }).each { |row|
          cookie = HTTP::Cookie.new({}.tap { |attrs|
              attrs[:name]        = row['name']
              attrs[:value]       = row['value']
              attrs[:domain]      = row['host']
              attrs[:path]        = row['path']
              attrs[:expires_at]  = Time.at(row['expiry'])
              attrs[:accessed_at] = Time.at(row['lastAccessed'])
              attrs[:created_at]  = Time.at(row['creationTime'])
              attrs[:secure]      = row['isSecure'] != 0
              attrs[:httponly]    = row['isHttpOnly'] != 0
            })

          yield cookie
        }
      end
      self
    end

    def clear
      @db.execute("DELETE FROM moz_cookies")
      self
    end

    def count
      @st_count ||=
        @db.prepare("SELECT COUNT(id) FROM moz_cookies")

      @st_count.execute.first[0]
    end
    protected :count

    def empty?
      count == 0
    end

    def cleanup(session = false)
      now = Time.now
      all_cookies = []

      @st_delete_expired ||=
        @db.prepare("DELETE FROM moz_cookies WHERE expiry < :expiry")

      @st_overusing_domains ||=
        @db.prepare(<<-'SQL')
                     SELECT LTRIM(host, '.') domain, COUNT(*) count
                       FROM moz_cookies
                       GROUP BY domain
                       HAVING count > :count
                    SQL

      @st_delete_per_domain_overuse ||=
        @db.prepare(<<-'SQL')
                     DELETE FROM moz_cookies WHERE id IN (
                       SELECT id FROM moz_cookies
                         WHERE LTRIM(host, '.') = :domain
                         ORDER BY creationtime
                         LIMIT :limit)
        SQL
      @st_delete_total_overuse ||=
        @db.prepare(<<-'SQL')
                     DELETE FROM moz_cookies WHERE id IN (
                       SELECT id FROM moz_cookies ORDER BY creationTime ASC LIMIT :limit
                     )
        SQL

      @st_delete_expired.execute({ 'expiry' => now.to_i })

      @st_overusing_domains.execute({
          'count' => HTTP::Cookie::MAX_COOKIES_PER_DOMAIN
        }).each { |row|
        domain, count = row['domain'], row['count']

        @st_delete_per_domain_overuse.execute({
            'domain' => domain,
            'limit' => count - HTTP::Cookie::MAX_COOKIES_PER_DOMAIN,
          })
      }

      overrun = count - HTTP::Cookie::MAX_COOKIES_TOTAL

      if overrun > 0
        @st_delete_total_overuse.execute({ 'limit' => overrun })
      end

      @gc_index = 0
    end
  end
end
