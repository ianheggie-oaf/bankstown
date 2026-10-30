#!/usr/bin/env ruby
# frozen_string_literal: true

# Scrapes development applications for Canterbury-Bankstown Council.
#
# The council's DA tracker lists every application lodged in a period (this
# week, this month, last month and so on) on a single page with no paging.
# Each application is an article card holding the reference, a
# "Type - description" paragraph and dt/dd pairs for Address and Lodged.
# It covers DAs, complying development and construction certificates,
# including those from private certifiers.
#
# DAs on exhibition are only published on the NSW Planning Portal, under PAN
# references, so they are not scraped here.
#
# See https://github.com/planningalerts-scrapers/issues/issues/1459

require "bundler/setup"
Bundler.require

require "scraperwiki"
require "mechanize"
require "date"

class Scraper
  BASE_URL = "https://eplanning.cbcity.nsw.gov.au"
  LIST_URL = "#{BASE_URL}/ApplicationSearch/SearchByLodgementDate?mode=view-applications-lodged&filter=".freeze

  # Last month as well as this month, so there are always at least 30 days of
  # applications early in the month
  DEFAULT_PERIODS = %w[thismonth lastmonth].freeze
  PERIODS = %w[yesterday thisweek lastweek thismonth lastmonth].freeze

  def self.run
    new.run
  end

  def initialize
    @agent = Mechanize.new
    if ENV["MORPH_AUSTRALIAN_PROXY"]
      # On morph.io set the environment variable MORPH_AUSTRALIAN_PROXY to
      # http://morph:password@au.proxy.oaf.org.au:8888 replacing password with
      # the real password.
      puts "Using Australian proxy..."
      @agent.agent.set_proxy(ENV["MORPH_AUSTRALIAN_PROXY"])
    end
    @debug = !ENV["MORPH_DEBUG"].to_s.empty?
    @saved = 0
  end

  def run
    puts "Running ruby #{RUBY_VERSION}"
    periods.each_with_index do |period, index|
      sleep 1 if index.positive?
      scrape_period(period)
    end
    puts "Finished - added #{@saved} records"
  end

  private

  # MORPH_PERIOD picks a single period, for example lastweek, for data recovery
  def periods
    period = ENV["MORPH_PERIOD"].to_s
    return DEFAULT_PERIODS if period.empty?
    return [period] if PERIODS.include?(period)

    raise "Unknown MORPH_PERIOD #{period.inspect}, expected one of #{PERIODS.join(', ')}"
  end

  def scrape_period(period)
    url = LIST_URL + period
    page = @agent.get(url)
    summary = page.at("#application-search-results .results-summary-title")
    raise "No results summary found at #{url}" unless summary

    expected = clean_text(summary.text)[/\A(\d+) applications? found/, 1]
    raise "Unexpected results summary #{clean_text(summary.text).inspect} at #{url}" unless expected

    cards = page.search("article.application-result-card")
    raise "Expected #{expected} applications but found #{cards.size} at #{url}" unless cards.size == expected.to_i

    cards.each { |card| save(parse_card(card)) }
    puts "Finished #{period} - processed #{cards.size} records"
  end

  def parse_card(card)
    link = card.at("a.application-details-link")
    fields = card_fields(card)
    {
      "council_reference" => clean_text(link.text),
      "address" => fields.fetch("Address"),
      "description" => description(card),
      "info_url" => URI.join(BASE_URL, link["href"]).to_s,
      "date_scraped" => Date.today.to_s,
      "date_received" => Date.strptime(fields.fetch("Lodged"), "%d/%m/%Y").to_s,
    }
  end

  # Maps each dt label to its dd value, keeping the first of any repeated label
  def card_fields(card)
    card.search("dt").each_with_object({}) do |dt, fields|
      fields[clean_text(dt.text)] ||= clean_text(dt.next_element&.text)
    end
  end

  # The description starts with the application type, for example
  # "Development Application - Construction of a dual occupancy"
  def description(card)
    text = clean_text(card.at("p.application-result-description")&.text)
    _type, description = text.split(" - ", 2)
    description.to_s.empty? ? text : description
  end

  # Collapses whitespace, including the non-breaking spaces used in addresses
  def clean_text(text)
    text.to_s.gsub(/[[:space:]]+/, " ").strip
  end

  def save(record)
    puts "RECORD: #{record.inspect}" if @debug
    ScraperWiki.save_sqlite(["council_reference"], record)
    @saved += 1
  end
end

Scraper.run if __FILE__ == $PROGRAM_NAME
