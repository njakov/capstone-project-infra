# Predlog strukture praktičnog i analitičkog dela diplomskog rada

## Kontekst dokumenta

Ovaj dokument je analiza predložene strukture praktičnog dela (glava 3, infrastruktura; glava 4, proces isporuke softvera) i analitičkog dela (glava 5) diplomskog rada, urađena na osnovu koda u dva repozitorijuma:

- `capstone-project-infra` — infrastruktura kao kod (Terraform) na Google Cloud Platform-u (GCP): mreža, GKE, Cloud SQL, Artifact Registry, IAM, CI izvršioci (runner-i), monitoring.
- `capstone-project-app` — Spring PetClinic aplikacija (Java 17, Spring Boot), Dockerfile, Helm chart i GitHub Actions workflow-i za build, release i deploy.

Analiza se oslanja isključivo na ono što je realizovano u kodu. Ključni izvori u repozitorijumima:

- `capstone-project-infra/README.md`
- `capstone-project-infra/docs/adr/001-runner-isolation.md` (ADR 001)
- `capstone-project-infra/docs/arc-cutover.md`
- `capstone-project-infra/docs/monitoring.md`
- `capstone-project-infra/Codebase_Architecture_and_Automation_Summary.md`
- `capstone-project-infra/.github/workflows/infra-pipeline.yml`
- `capstone-project-app/README.md`
- `capstone-project-app/.github/workflows/` (`pr-release.yml`, `deploy-dev.yml`, `main-release.yml`, `manual-deploy.yml`)

### Prvobitno predložena struktura (koja se ovde kritikuje)

Arhitektura i implementacija sistema (praktični deo)

- 3.1. Arhitektura oblačne infrastrukture na Google Cloud Platform (GCP)
- 3.2. Izgradnja IaC modula (OpenTofu/Terraform: VPC, GKE, Cloud SQL, Artifact Registry)
- 3.3. Kontejnerizacija aplikacije i upravljanje Helm izdanjima
- 3.4. Konfiguracija CI/CD cevovoda putem GitHub Actions (BuildKit, Workload Identity, sigurnost isporuke)

Analiza, verifikacija i evaluacija rezultata

- 4.1. Izvođenje i automatizacija testova (aplikativni i infrastrukturni testovi)
- 4.2. Evaluacija podudarnosti okruženja (dev vs prod) i uštede resursa
- 4.3. Monitoring i opservabilnost sistema (Prometheus i Grafana)

Zaključak

- Rezime postignutih rezultata, ocena ispunjenosti ciljeva i smernice za dalji razvoj.

### Glavni zaključak

Prvobitna struktura nabraja alate, a sakriva ono čime se implementacija zaista ističe: model bezbednosti i identiteta, izolaciju okruženja kroz odvojene GCP projekte, arhitekturu CI izvršilaca i fazno provizionisanje infrastrukture. Pored toga, tri tvrdnje iz prvobitne strukture nisu tačne u odnosu na kod (odeljak 1).

---

## 1. Netačnosti u prvobitnoj strukturi

### 1.1. OpenTofu se ne koristi

Fajl `.terraform-version` sadrži `1.16.0`. README i ADR 001 pominju isključivo HashiCorp Terraform 1.16.x. Ni jedan fajl u oba repozitorijuma ne pominje `tofu` niti `opentofu`. Naslov 3.2 treba da glasi „Terraform“.

### 1.2. „Workload Identity“ u 3.4 je dvosmislen pojam

Sistem **ne koristi** Workload Identity Federation (GitHub OIDC → GCP). U app workflow-ima dozvola `id-token: write` namerno ne postoji, a ADR 001 to navodi kao prihvaćeni rizik. Koriste se dva druga mehanizma:

- **GKE Workload Identity** za ARC podove: Kubernetes nalog `arc-runners/arc-runner` preuzima GCP nalog `github-app-runner-sa-{env}`.
- **Servisni nalog zakačen za GCE VM**, preko metadata servera, za infra runner (`github-infra-runner-sa-{env}`).

Ta razlika čini ceo model poverenja i u radu mora biti eksplicitna.

### 1.3. „Infrastrukturni testovi“ u 4.1 obećavaju više nego što postoji

Ne postoje `terraform test`, Terratest niti automatski testovi nad živom infrastrukturom. Postoje:

- statičke provere u `infra-pipeline.yml`: `terraform fmt`, `terraform validate`, TFLint, `trivy config` i grep zaštita koja obara job ako se `google_project_iam_*` pojavi u day-2 putanjama;
- ručni negativni IAM testovi (`scripts/negative-iam-tests.sh`, koji sam navodi da nije CI gate);
- ručne verifikacione kapije (Gate C i Gate E u `docs/arc-cutover.md`).

Na strani aplikacije, MySQL integracioni testovi imaju `@Testcontainers(disabledWithoutDocker = true)`. ARC runner nema Docker daemon, pa se ti testovi **u CI-ju preskaču**. PostgreSQL testovi koriste Docker Compose i takođe se izvršavaju samo lokalno. JaCoCo postoji u build-u, ali prag pokrivenosti nije nametnut.

---

## 2. Šta iz koda nedostaje u strukturi

| Poglavlje | Šta pokriva | Šta iz koda nedostaje |
|---|---|---|
| 3.1 | GCP, GKE, Cloud SQL | Dva GCP projekta, infra i app ravan, dva repozitorijuma |
| 3.2 | network, gke, cloud-sql, artifact-registry | bootstrap-iam, identity, runner, arc, external-secrets, middleware, network-peering; fazno provizionisanje; upravljanje stanjem |
| 3.3 | Dockerfile, Helm | Spring Boot prilagođavanja, Cloud SQL Auth Proxy, SecretProviderClass, fail-closed vrednosti |
| 3.4 | GitHub Actions, BuildKit | ARC i izolacija runner-a, rootless BuildKit protokol, infra pipeline, SemVer i model promocije |
| 4.1 | Testovi | Bezbednosna skeniranja, negativni IAM testovi, verifikacione kapije |
| 4.2 | dev i prod | Namerne razlike između okruženja, kvantitativna analiza troškova |
| 4.3 | Prometheus i Grafana | ServiceMonitor, PrometheusRule i dashboard kao kod; prilagođavanje GKE-u |

### a) Model bezbednosti i identiteta (najveći propust)

Ovo je najobimniji deo infra repozitorijuma, a u prvobitnoj strukturi je sveden na „sigurnost isporuke“. U kodu postoji:

- keyless pristup, bez JSON ključeva servisnih naloga;
- `terraform-sa` sa ulogom `projectIamAdmin` ograničenom CEL uslovom (`modifiedGrantsByRole` sa listom dozvoljenih uloga), koji se **gasi** posle bootstrap-a (`scripts/lock-terraform-sa.sh`);
- day-2 runner (`github-infra-runner-sa-{env}`) bez `projectIamAdmin` i bez project-level `serviceAccountAdmin` i `serviceAccountUser`;
- prilagođene uloge `arcAppDeploy` i `infraRunnerWorkloadIdentityAdmin`; ova druga je vezana uslovom `hasOnly(['roles/iam.workloadIdentityUser'])`;
- IAM dozvole na nivou resursa: Artifact Registry repozitorijum, pojedinačne tajne u Secret Manager-u, Cloud SQL instanca po imenu (`cloudsql.client` sa uslovom);
- Kubernetes RBAC za app runner ograničen na namespace `petclinic` i čitanje Service-a u `ingress-nginx`;
- NetworkPolicy sa default-deny pravilom na GKE Dataplane V2;
- non-root kontejneri (aplikacija kao UID 10001).

Akademski, ovo je primena principa najmanjih privilegija i smanjenja radijusa štete (blast radius). To je ono što rad podiže iznad opisa instalacije alata.

### b) Izolacija okruženja kao granica projekta

Dev i prod su odvojeni GCP projekti (dev: `project-62ebde90-46b7-4e70-b59`, prod: `petclinic-gke-prod`). ADR 001 obrazlaže zašto: trial nalog nema organizaciju, foldere, deny politike ni VPC Service Controls, pa je granica projekta jedina pouzdana granica izolacije. Ta odluka objašnjava veliki deo ostatka dizajna.

### c) Mrežna arhitektura

Treba opisati:

- infra VPC (bootstrap) i app VPC (env) povezane dvosmernim peering-om, uz plan CIDR opsega bez preklapanja, različit za dev i prod;
- privatni GKE klaster (privatni čvorovi i privatni IP endpoint);
- **DNS endpoint kontrolne ravni**: peering nije tranzitivan, a klasteri na Regular kanalu izlažu kontrolnu ravan preko Private Service Connect-a, pa Terraform i Helm pristupaju klasteru preko DNS imena. Kubernetes tokeni i klijentski sertifikati na tom imenu su isključeni, pristup je isključivo preko Google IAM-a (`container.clusters.connect`);
- master authorized networks za IP endpoint (samo app subnet; infra subnet nema rutu do kontrolne ravni);
- Cloud NAT za izlazni saobraćaj bez javnih IP adresa;
- IAP SSH ograničen na tag `infra-runner`;
- Private Service Access za Cloud SQL (bez javne IPv4 adrese, `ENCRYPTED_ONLY`);
- ingress-nginx LoadBalancer ograničen na `allowed_source_ranges`.

### d) Arhitektura CI izvršilaca (runner-a)

Ovo je verovatno najoriginalniji deo rada:

- odvojene infra i app ravan izvršilaca: GCE VM `runner-vm-infra-{env}` u infra VPC-u za Terraform, a ARC ephemeral scale set-ovi (`petclinic-arc-{env}`) u GKE-u za aplikaciju;
- poseban node pool `runners` sa taint-om `github.runner=true:NoSchedule`, na Ubuntu slici (`UBUNTU_CONTAINERD`) jer rootless BuildKit to zahteva; aplikativni pool ostaje na COS-u;
- rootless BuildKit kao sidecar u runner podu, prema zvaničnom `job.rootless.yaml` (UID 1000, `--oci-worker-no-process-sandbox`), bez DinD-a, bez `privileged` i bez Docker socket-a;
- protokol između runner-a i sidecar-a preko request fajla na zajedničkom `emptyDir` volumenu (`/buildkit-work`), definisan u composite action-u `buildkit-build`;
- Trivy skeniranje tar arhive image-a **pre** push-a u registar preko alata `crane`; sidecar nikada ne dobija kredencijale za registar;
- istorija razvoja kroz commit-ove (neuspeli pristup sa `hostUsers: false` i ručnim pokretanjem `buildkitd`, zatim BuildKit spike Job), koja pokazuje inženjerski proces.

### e) Upravljanje tajnama

Treba opisati:

- Google Secret Manager kao centralno skladište;
- GKE Secrets Store CSI drajver (`SecretProviderClass`) koji montira korisničko ime, lozinku i JDBC URL baze kao fajlove, zajedno sa Spring `SPRING_CONFIG_IMPORT=configtree:/mnt/secrets/`;
- External Secrets Operator koji sinhronizuje privatni ključ GitHub App-a u Kubernetes secret `arc-github-app`;
- zašto Terraform ne sme da poseduje taj secret: refresh bi upisao PEM u Terraform state; `removed` blok uklanja resurs iz stanja bez brisanja objekta;
- odvojenu root lozinku baze bez accessor dozvole za aplikaciju;
- Grafana admin lozinku iz GitHub Environment secret-a.

### f) Upravljanje Terraform stanjem i bezbednost plana

Treba opisati:

- GCS bucket `terraform-state-bucket-${project_id}` po projektu, sa CMEK enkripcijom, versioning-om, uniform bucket-level access i public access prevention (`scripts/create-bucket.sh`);
- plan fajl čuvan u bucket-u (`plans/`) umesto u GitHub artefaktima, jer sadrži tajne, uz lifecycle pravilo od jednog dana kao rezervu;
- apply tačno onog plana koji je generisan u istom pokretanju;
- razrešavanje ref-a u commit SHA samo jednom po pokretanju, tako da svi job-ovi koriste isti commit;
- prod gate: apply i destroy samo sa vrha `main` grane i fail-closed provera da `prod` Environment ima required reviewers;
- `project_id` se čita iz `terraform.tfvars`, a ne iz GitHub varijabli.

### g) Model izdanja

Treba opisati:

- PR Gatekeeper (`pr-release.yml`): Checkstyle, testovi, BuildKit build, Trivy, push u dev registar, bez deploy-a;
- `deploy-dev.yml`: automatski deploy na dev klaster pri svakom push-u na `main`;
- `main-release.yml`: SemVer tag preko `scripts/bump_version.py`, push samo u prod registar, bez deploy-a;
- `manual-deploy.yml`: ručni deploy izabranog tag-a; za prod prihvata samo SemVer tag i proverava da image postoji u registru tog okruženja;
- odvojene registre po okruženju (`petclinic-repo-dev`, `petclinic-repo-prod`).

Treba otvoreno analizirati da se **prod image ponovo gradi** u `main-release.yml`, umesto da se isti digest promoviše iz dev registra. To odstupa od principa „build once, deploy many“ i direktna je posledica izolacije projekata. Rollback postoji samo kao ručni deploy ranijeg tag-a i kroz Helm istoriju.

### h) ADR i runbook-ovi

ADR 001 sa odeljcima „Honest residuals“ i „Accepted risks“, kao i `docs/arc-cutover.md` i `docs/monitoring.md`, predstavljaju metodološku vrednost rada i treba ih pomenuti.

---

## 3. Predlog konačne strukture

Praktični deo je podeljen na dve glave. Glava 3 opisuje kako se infrastruktura postavlja i menja. Glava 4 opisuje kako se softver gradi, raspoređuje i prati. PetClinic je primer aplikacije na kojoj se to pokazuje, a ne predmet glave.

### Naslov glave 4

**Automatizacija procesa isporuke softvera**

U naslovu nema ni Kubernetes-a ni GitHub Actions-a.

- Kubernetes (GKE) je predmet glave 3: klaster, mreža, node pool-ovi, RBAC. U glavi 4 se na taj klaster raspoređuje preko Helm-a, pa Kubernetes i Helm stoje u naslovu odeljka 4.1.
- GitHub Actions pokreće i cevovod za infrastrukturu (glava 3) i cevovod za isporuku (glava 4). Ime alata ne razdvaja glave i zato stoji u naslovu odeljka 4.3.

### Glava 3. Automatizacija upravljanja infrastrukturom u Google Cloud okruženju

#### 3.1. Ograničenja okruženja i arhitektonske odluke

- Ograničenja trial naloga (bez organizacije, VPC-SC i deny politika; budžet)
- Metodologija beleženja odluka (ADR 001)

*Obrazloženje:* odluke treba da prethode opisu implementacije. Bez ograničenja trial naloga, izolacija preko projekata i niz drugih rešenja deluju proizvoljno.

#### 3.2. Arhitektura sistema i mrežna izolacija

- Dva repozitorijuma i dva projekta; infra i app ravan; dijagram arhitekture
- Infra i app VPC, peering, plan CIDR opsega, privatni GKE i DNS endpoint, Cloud NAT, IAP, Private Service Access, NetworkPolicy

*Obrazloženje:* zamenjuje prvobitnu 3.1 i daje joj sadržaj. Mrežni sloj je temelj svih kasnijih bezbednosnih tvrdnji.

#### 3.3. Infrastruktura kao kod (Terraform)

- 3.3.1. Modularna struktura i kompozicija okruženja (`modules/` i `environments/bootstrap|dev|prod`); determinističko imenovanje resursa kao ugovor između dva repozitorijuma
- 3.3.2. Fazno provizionisanje: `setup_gcp.sh` → bootstrap → day-2 (problem „kokoške i jajeta“); ARC u dve faze (`arc_install_charts`)
- 3.3.3. Upravljanje stanjem i plan artefaktima; `moved` i `removed` blokovi
- 3.3.4. Ključni resursi: GKE (zonalni dev i regionalni prod, dva node pool-a, taint, COS i Ubuntu), Cloud SQL, Artifact Registry, middleware (ingress-nginx, kube-prometheus-stack)

*Obrazloženje:* u IaC-u je vredan dizajn, a ne spisak resursa. Prvobitna 3.2 pominje četiri modula i prećutkuje šest (bootstrap-iam, identity, runner, arc, external-secrets, middleware, network-peering).

#### 3.4. Identiteti, pristup i tajne

- 3.4.1. Keyless autentikacija i podela identiteta (`terraform-sa`, infra runner SA, app runner SA, app SA, External Secrets SA, node SA)
- 3.4.2. IAM uslovi (CEL), prilagođene uloge i zaključavanje bootstrap identiteta
- 3.4.3. Kubernetes RBAC, Pod Security Admission, non-root kontejneri
- 3.4.4. Tajne: Secret Manager, Secrets Store CSI drajver, External Secrets Operator, zaštita Terraform stanja od tajni

*Obrazloženje:* najobimniji deo koda zaslužuje zasebno poglavlje. Ono daje model pretnji koji se zatim verifikuje u 5.3.

#### 3.5. Cevovod za izmene infrastrukture

- Statičke provere, plan → apply istog artefakta, SHA pinning, prod gate
- Gde se job izvršava (infra runner) razrađeno je u 4.2, zajedno sa izvršiocima isporuke, jer je to jedan dizajn (ADR 001)

*Obrazloženje:* cevovod koji menja infrastrukturu pripada glavi o upravljanju infrastrukturom. GitHub Actions je ovde samo orkestrator, isti kao u glavi 4.

### Glava 4. Automatizacija procesa isporuke softvera

#### 4.1. Kontejnerizacija i raspoređivanje pomoću Helm-a

- Spring PetClinic kao primer aplikacije, onoliko koliko isporuka od nje traži (Actuator probe i metrika, `configtree`, MySQL profil)
- Dockerfile (Temurin 17 JRE base image zakačen za digest, korisnik UID 10001) i Cloud SQL Auth Proxy sidecar (`--private-ip`)
- Struktura Helm chart-a, vrednosti po okruženju (`values-dev.yaml`, `values-prod.yaml`), vrednosti vezane za projekat koje namerno padaju bez `--set`

*Obrazloženje:* predmet odeljka je kontejner i raspoređivanje na klaster. PetClinic služi kao primer.

#### 4.2. Arhitektura CI izvršilaca

- Infra GCE runner u odnosu na ephemeral ARC scale set-ove; tainted node pool; autentikacija ARC-a prema GitHub-u preko GitHub App-a
- Rootless BuildKit sidecar: zašto ne DinD, protokol preko request fajla, Trivy pre `crane` push-a

*Obrazloženje:* ovo je tehnički najsloženiji i najoriginalniji deo rada. U prvobitnoj strukturi je sakriven u zagradi. Infra i app ravan ostaju zajedno jer ih ADR 001 tretira kao jedan model izolacije. Odeljak 3.5 samo upućuje ovde za mesto izvršavanja Terraform job-a.

#### 4.3. CI/CD cevovodi u GitHub Actions-u i upravljanje verzijama

- PR Gatekeeper, `deploy-dev`, SemVer release, ručni deploy i rollback na raniji tag

*Obrazloženje:* odvajanje 4.2 (gde se posao izvršava) od 4.3 (šta se izvršava) daje čitljiviji tok. GitHub Actions je imenovan ovde, ne u naslovu glave.

#### 4.4. Monitoring i alerting

- ServiceMonitor, PrometheusRule i Grafana dashboard kao kod u Helm chart-u; scrape putanja `/actuator/prometheus`
- Alerti `PetclinicInstanceDown`, `PetclinicHighCpuUsage`, `PetclinicHighMemoryUsage`
- kube-prometheus-stack (instalacija je middleware u 3.3.4; ovde je šta se nadgleda i kako je prilagođeno GKE-u: isključeni scrape-ovi za control plane, kube-proxy i CoreDNS)

*Obrazloženje:* prvobitna analitička 4.3 opisuje implementaciju, pa pripada glavi 4. U glavi 5 ostaje dokaz da sistem radi.

### Glava 5. Verifikacija, analiza i evaluacija

#### 5.1. Metodologija verifikacije

Šta se smatra dokazom; piramida provera (statičke, jedinične, integracione, bezbednosne, prihvatne); jasna podela na automatske i ručne provere.

*Obrazloženje:* daje naučni okvir i unapred razdvaja automatsko od ručnog, čime se izbegava preterivanje u tvrdnjama.

#### 5.2. Statička analiza, testovi i bezbednosna skeniranja

- Checkstyle i nohttp pravilo, jedinični i kontrolerski testovi; Testcontainers testovi u CI-ju (preskočeni, uz objašnjenje)
- TFLint, `trivy config` nad Terraform kodom, Trivy nad image-om (HIGH i CRITICAL obaraju job)
- Studija slučaja: commit „Pin embedded Tomcat to 11.0.26 so the image passes the Trivy critical gate“, kao konkretan dokaz da bezbednosna kapija radi

#### 5.3. Provera pristupa i izolacije

- Negativni IAM testovi (očekivan `PERMISSION_DENIED`): `terraform-sa` ne može dodeliti `roles/owner` niti kreirati GKE i Cloud SQL; infra runner ne može menjati IAM politiku nad `terraform-sa`; nema project-level Artifact Registry dozvola za app runner i node SA
- NetworkPolicy smoke test (HTTPS ka GitHub-u i registru radi, pristup PetClinic ClusterIP-u ne radi)
- Provera pod spec-a BuildKit sidecar-a i BuildKit spike Job

*Obrazloženje:* tvrdnje iz 3.4 i 4.2 bez ovoga ostaju nepotvrđene. Negativni testovi su jak dokaz jer pokazuju šta se **ne može** uraditi.

#### 5.4. Podudarnost okruženja i analiza troškova

- Isti moduli, različiti `terraform.tfvars`; tabela namernih razlika:

| Sloj | Dev | Prod |
|---|---|---|
| GKE kontrolna ravan | Zonalna (`europe-west1-c`) | Regionalna (`europe-west1`) |
| App node pool | 1 zona, 1–2 čvora `e2-standard-2` | 2 zone, 1–2 čvora po zoni `e2-standard-2` |
| Cloud SQL | `db-f1-micro`, `ZONAL` | `db-g1-small`, `REGIONAL` |
| Replike aplikacije | 1 | 2 |

- Ponovni build prod image-a u odnosu na promociju istog digest-a
- Troškovi: procena iz ADR-a (oko 60 USD naspram 300 USD kredita), besplatna kvota za zonalni klaster, kratki prozori za prod okruženje i redosled uništavanja (env pa bootstrap)

Procenu treba potkrepiti **stvarnim podacima iz GCP Billing-a**. Naslov „uštede resursa“ traži merenje, ne procenu.

#### 5.5. Provera rada sistema

- Trajanje pipeline-ova i prvog apply-a (ADR 001 predviđa 45–90 minuta za prod)
- Demonstracija alerta `PetclinicInstanceDown` (skaliranje Deployment-a na 0)
- Opciono: test opterećenja pomoću postojećeg `src/test/jmeter/petclinic_test_plan.jmx` uz Grafana grafike

#### 5.6. Ograničenja i preostali rizici

- HTTP bez TLS-a (nema cert-manager-a)
- Ručna registracija infra runner-a preko IAP SSH
- ARC runner-i i aplikacija u istom klasteru; kompromitovan ARC sa deploy pravima može menjati Deployment-e u tom klasteru
- Runner kontejner pokrenut kao UID 0 i Unconfined seccomp/AppArmor na BuildKit sidecar-u
- Infra runner zadržava `networkAdmin` i `*admin` uloge unutar svog projekta
- DNS endpoint kontrolne ravni nema mrežnu listu dozvola (samo IAM)
- Nema GitHub OIDC-a, SLSA provenance-a ni automatskog rollback testa
- Alertmanager bez spoljnih receiver-a
- App action-i zakačeni za tag, a infra action-i za SHA
- PR-ovi pomeraju `latest` tag u dev registru

*Obrazloženje:* ADR 001 već sadrži ovu listu. Otvoreno navođenje ograničenja je akademski standard i štiti rad od pitanja na odbrani na koja kandidat nema odgovor.

### Glava 6. Zaključak

Rezime postignutog u odnosu na ciljeve iz 3.1 i smernice za dalji razvoj, koje prirodno proizilaze iz 5.6:

- Workload Identity Federation za GitHub;
- cosign potpisivanje i SLSA provenance, Binary Authorization;
- cert-manager i TLS;
- GitOps (Argo CD);
- `terraform test`;
- automatski rollback;
- promocija istog image digest-a između okruženja;
- zaseban klaster za runner-e.

---

## 4. Napomene pre pisanja

- U infra repozitorijumu postoje necommit-ovane izmene u `modules/gke/main.tf` i `modules/identity/main.tf`: Pod Security Admission labele na namespace-u `petclinic` i `trivy:ignore` komentari. Ako se opisuju u 3.4.3, treba ih commit-ovati i primeniti pre predaje, da bi rad odgovarao kodu.
- `Codebase_Architecture_and_Automation_Summary.md` je dobra osnova za poglavlja 3.3–4.3 i 5.6, jer opisuje samo ono što kod zaista radi.
