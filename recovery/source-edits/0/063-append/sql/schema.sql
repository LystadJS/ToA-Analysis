
CREATE TABLE IF NOT EXISTS us_goods_trade (
  iso3 char(3) NOT NULL REFERENCES country, year integer NOT NULL,
  census_code text NOT NULL, exports_usd bigint NOT NULL, imports_usd bigint NOT NULL,
  source_id text NOT NULL REFERENCES source, PRIMARY KEY (iso3,year,census_code)
);
CREATE TABLE IF NOT EXISTS us_contribution (
  iso3 char(3) NOT NULL REFERENCES country, source_id text NOT NULL REFERENCES source,
  year integer NOT NULL, actor text NOT NULL, cents bigint, known integer NOT NULL,
  records integer NOT NULL, PRIMARY KEY (iso3,source_id,year,actor),
  CHECK (known>=0 AND records>=known AND records>0), CHECK ((known=0)=(cents IS NULL))
);
CREATE TABLE IF NOT EXISTS us_relationship (
  iso3 char(3) NOT NULL REFERENCES country, source_id text NOT NULL REFERENCES source,
  name text NOT NULL, kind text NOT NULL, status text NOT NULL,
  first_year integer, last_year integer, detail text NOT NULL, citation text NOT NULL,
  PRIMARY KEY (iso3,source_id,name)
);
