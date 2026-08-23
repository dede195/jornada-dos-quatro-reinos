function normalizeImportText(value) {
  return String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim().toLowerCase();
}

function downloadSchoolTemplate() {
  if (!window.XLSX) {
    alert('O gerador de planilhas não carregou. Atualize a página.');
    return;
  }
  const rows = [
    { Turma: '3º A', Etapa: '3º ano', Professor: 'Nome igual ao cadastro', Estudante: 'Ana' },
    { Turma: '3º A', Etapa: '3º ano', Professor: 'Nome igual ao cadastro', Estudante: 'Bruno' },
    { Turma: '4º B', Etapa: '4º ano', Professor: 'Outro professor', Estudante: 'Caio' }
  ];
  const sheet = XLSX.utils.json_to_sheet(rows);
  const book = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(book, sheet, 'Turmas');
  XLSX.writeFile(book, 'modelo-importacao-jornada.xlsx');
}

async function importSchoolSpreadsheet(file, schoolId, team, existingClasses, existingStudents, status, role) {
  if (!file) {
    status.className = 'import-result error';
    status.textContent = 'Escolha uma planilha primeiro.';
    return;
  }
  if (!window.XLSX) {
    status.className = 'import-result error';
    status.textContent = 'O leitor de planilhas não carregou. Atualize a página.';
    return;
  }
  status.className = 'import-result';
  status.textContent = 'Lendo e conferindo a planilha...';
  try {
    const book = XLSX.read(await file.arrayBuffer(), { type: 'array' });
    const sheet = book.Sheets[book.SheetNames[0]];
    const rawRows = XLSX.utils.sheet_to_json(sheet, { defval: '' });
    if (!rawRows.length) throw new Error('A planilha está vazia.');

    const stageMap = {
      ei: 'educacao_infantil', infantil: 'educacao_infantil', 'educacao infantil': 'educacao_infantil',
      '1': '1_ano', '1 ano': '1_ano', '1o ano': '1_ano',
      '2': '2_ano', '2 ano': '2_ano', '2o ano': '2_ano',
      '3': '3_ano', '3 ano': '3_ano', '3o ano': '3_ano',
      '4': '4_ano', '4 ano': '4_ano', '4o ano': '4_ano',
      '5': '5_ano', '5 ano': '5_ano', '5o ano': '5_ano'
    };
    const teacherMap = new Map();
    team.forEach(member => {
      const profile = Array.isArray(member.perfis) ? member.perfis[0] : member.perfis;
      if (profile?.nome_exibicao) teacherMap.set(normalizeImportText(profile.nome_exibicao), member.usuario_id);
    });
    const classMap = new Map(existingClasses.map(item => [`${normalizeImportText(item.nome)}|${item.etapa}`, item.id]));
    const studentSet = new Set(existingStudents.map(item => `${item.turma_id}|${normalizeImportText(item.apelido)}`));
    let classesCreated = 0, studentsCreated = 0, ignored = 0;
    const problems = [];

    for (let i = 0; i < rawRows.length; i++) {
      const clean = {};
      Object.entries(rawRows[i]).forEach(([key, value]) => clean[normalizeImportText(key)] = String(value).trim());
      const className = clean.turma;
      const stageName = stageMap[normalizeImportText(clean.etapa).replace('º', 'o')];
      const teacherName = clean.professor;
      const studentName = clean.estudante;
      if (!className || !stageName || !teacherName || !studentName) {
        problems.push(`Linha ${i + 2}: falta Turma, Etapa, Professor ou Estudante.`);
        continue;
      }
      const teacherId = teacherMap.get(normalizeImportText(teacherName));
      if (!teacherId) {
        problems.push(`Linha ${i + 2}: professor “${teacherName}” ainda não entrou na escola.`);
        continue;
      }
      const classKey = `${normalizeImportText(className)}|${stageName}`;
      let classId = classMap.get(classKey);
      if (!classId) {
        const { data: newClass, error: classError } = await databaseClient.from('turmas').insert({
          escola_id: schoolId, professora_id: teacherId, nome: className, etapa: stageName
        }).select('id').single();
        if (classError) {
          problems.push(`Linha ${i + 2}: não foi possível criar a turma ${className}.`);
          continue;
        }
        classId = newClass.id;
        classMap.set(classKey, classId);
        classesCreated++;
      }
      const studentKey = `${classId}|${normalizeImportText(studentName)}`;
      if (studentSet.has(studentKey)) {
        ignored++;
        continue;
      }
      const { error: studentError } = await databaseClient.from('alunos').insert({ turma_id: classId, apelido: studentName });
      if (studentError) {
        problems.push(`Linha ${i + 2}: não foi possível adicionar ${studentName}.`);
        continue;
      }
      studentSet.add(studentKey);
      studentsCreated++;
    }

    status.className = `import-result ${problems.length ? 'error' : 'success'}`;
    status.textContent = `Importação concluída: ${classesCreated} turma(s) e ${studentsCreated} estudante(s) criados; ${ignored} repetido(s) ignorado(s).${problems.length ? ` ${problems.length} linha(s) precisam de correção: ${problems.slice(0, 3).join(' ')}` : ''}`;
    if (classesCreated || studentsCreated) setTimeout(() => schoolAdminDashboard(schoolId, role), 2500);
  } catch (error) {
    status.className = 'import-result error';
    status.textContent = `Não foi possível importar: ${error.message}`;
  }
}
