defmodule Pokevestment.Repo.Migrations.AddPtcgoCodeIndexAndSeed do
  use Ecto.Migration

  def change do
    create index(:sets, [:ptcgo_code], where: "ptcgo_code IS NOT NULL")

    # Seed missing PTCGO codes for SV/ME era sets used in tournaments.
    # Confirmed via cross-referencing card names between TCGdex and Limitless.
    execute(
      """
      UPDATE sets SET ptcgo_code = v.code
      FROM (VALUES
        ('sv01',    'SVI'),
        ('sv02',    'PAL'),
        ('sv03',    'OBF'),
        ('sv03.5',  'MEW'),
        ('sv04',    'PAR'),
        ('sv04.5',  'PAF'),
        ('sv05',    'TEF'),
        ('sv06',    'TWM'),
        ('sv06.5',  'SFA'),
        ('sv07',    'SCR'),
        ('sv08',    'SSP'),
        ('sv08.5',  'PRE'),
        ('sv09',    'JTG'),
        ('sv10',    'DRI'),
        ('sv10.5b', 'BLK'),
        ('sv10.5w', 'WHT'),
        ('svp',     'SVP'),
        ('me01',    'MEG'),
        ('me02',    'PFL'),
        ('me02.5',  'ASC'),
        ('mep',     'MEP')
      ) AS v(set_id, code)
      WHERE sets.id = v.set_id AND sets.ptcgo_code IS NULL
      """,
      """
      UPDATE sets SET ptcgo_code = NULL
      WHERE id IN ('sv01','sv02','sv03','sv03.5','sv04','sv04.5','sv05','sv06','sv06.5','sv07','sv08','sv08.5','sv09','sv10','sv10.5b','sv10.5w','svp','me01','me02','me02.5','mep')
      """
    )
  end
end
