import xlsxwriter


def create_template(output_path: str) -> None:
    workbook = xlsxwriter.Workbook(output_path)

    header_format = workbook.add_format({"bold": True, "bg_color": "#EDEDED", "border": 1})
    cell_format = workbook.add_format({"border": 1})

    teams_ws = workbook.add_worksheet("Takimlar")
    teams_ws.write(0, 0, "Takım Adı", header_format)

    teams = [
        "Master Göztepe",
        "Nevşehir Ağıllı",
        "Arnavutköy Master",
        "Napoli Master",
        "Barış Master",
        "Gop",
        "Kuzey Master",
        "Wolf Master",
    ]

    for i, team in enumerate(teams, start=1):
        teams_ws.write(i, 0, team, cell_format)

    teams_ws.set_column(0, 0, 22)

    fixture_ws = workbook.add_worksheet("Fikstur")
    headers = ["Hafta", "Grup / Lig", "Ev Sahibi Takım", "Deplasman Takımı", "Tarih", "Saat"]
    for col, title in enumerate(headers):
        fixture_ws.write(0, col, title, header_format)

    fixture_ws.freeze_panes(1, 0)

    teams_range_formula = "='Takimlar'!$A$2:$A$500"
    for row in range(1, 100):
        fixture_ws.data_validation(
            row,
            2,
            row,
            2,
            {"validate": "list", "source": teams_range_formula, "ignore_blank": True},
        )
        fixture_ws.data_validation(
            row,
            3,
            row,
            3,
            {"validate": "list", "source": teams_range_formula, "ignore_blank": True},
        )

    fixture_ws.write(1, 0, 1, cell_format)
    fixture_ws.write(1, 1, "A", cell_format)
    fixture_ws.write(1, 2, "Master Göztepe", cell_format)
    fixture_ws.write(1, 3, "Nevşehir Ağıllı", cell_format)
    fixture_ws.write(1, 4, "2026-04-11", cell_format)
    fixture_ws.write(1, 5, "20:00", cell_format)

    fixture_ws.set_column(0, 0, 8)
    fixture_ws.set_column(1, 1, 12)
    fixture_ws.set_column(2, 3, 22)
    fixture_ws.set_column(4, 4, 12)
    fixture_ws.set_column(5, 5, 10)

    workbook.close()


if __name__ == "__main__":
    create_template("Fikstur_Sablonu_2.xlsx")
