-- MAQ CRM: expected close quarter and year on RFQs (e.g. Q3 2027).
-- Used by the Panametrics tracker ("Order expected" / "Year") and the Bureau Veritas tracker ("Closing Date").
-- Safe to re-run.
alter table opportunities add column if not exists expected_quarter text;
alter table opportunities add column if not exists expected_year smallint;
alter table opportunities drop constraint if exists opportunities_expected_quarter_check;
alter table opportunities add constraint opportunities_expected_quarter_check check (expected_quarter is null or expected_quarter in ('Q1','Q2','Q3','Q4'));
notify pgrst, 'reload schema';
