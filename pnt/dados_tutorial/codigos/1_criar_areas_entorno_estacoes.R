#Passo-a-passo do calculo do PNT
#1. Instalar pacotes e definir diretorio
#2. Conectar com OTP, abrir e limpar arquivos necessarios
#3. Criar areas no entorno das estacoes de transporte


#1. Instalar pacotes e definir diretorio
#1.1. Definir diretorio
setwd('C:/Users/berna/Desktop/tutorial_pnt')

#1.2.instalar pacote necessarios
install.packages('readr') #leitura e manipulacoes de dados em formato rds
install.packages('dplyr') #leitura e operacoes com tabelas
install.packages('data.table') #leitura e operacoes com tabelas
install.packages('sf') #leitura e manipulacoes de dados georreferenciados
install.packages('mapview') #visualizacoes de de dados georreferenciados
install.packages('beepr') #aviso sonoro de conclusao de tarefa
install.packages('purrr') #otimizacao de funcoes e manipulacao de vetores
install.packages('devtools') #ferramentas para desenvolvimento
devtools::install_local("./misc/opentripplanner-master_mode.zip") #interface com opentripplanner para roteamento de viagem


#1.3. Carregar pacotes necessarios
library(readr)
library(dplyr)
library(data.table)
library(sf)
library(mapview)
library(beepr)
library(purrr)
library(opentripplanner)


#1.4. Abrir o OTP
otp_dl_jar(path = "./otp/programs") #download otp
beep()


#1.5. Construir graph da rmb a partir da malha de rua.pbf - fazer uma unica vez
opentripplanner::otp_build_graph(otp = "otp/programs/otp.jar", 
                                 memory = 3000,
                                 dir = "otp", 
                                 router = "rmb") #inserir sigal da cidade ou rm desejada


#2. Conectar com OTP, abrir e limpar arquivos necessarios
#2.1. Abrir otp
otp_setup(otp = "otp/programs/otp.jar", 
          dir = "otp", 
          router = 'rmb', 
          port = 8080, 
          wait = FALSE)
beep()

#2.2. Conectar com malha da regiao metropolitana de Belem
otp_rm <- otp_connect(router = 'rmb')
beep()

#2.3. Abrir e filtrar  estacoes de transporte de media e alta capacidade para regiao e cidade desejada
tma_rm <- sf::st_read('./dados/estacoes_2019.shp') %>%
  mutate(Year = as.numeric(as.character(Year))) %>% #transforma a coluna de ano em valor numerico
  filter(Year < 2020, RT == 'Yes', Status == 'Operational', #filtrar estacoes de media e alta capacidade
         City == 'Belém') %>% #MUDAR NOME DA CIDADE PARA NUCLEO DA RM
  st_transform(., 4326)


#2.4. Limpar arquivo com latitude e longitude das estacoes
coords_tma_rm <- setDT(tma_rm) %>% select(City, Mode, Station, Year, Y, X) # criar arquivo com coordenadas
coords_tma_rm <- coords_tma_rm[, id_stop := 1:.N] #criar coluna de id das estacoes
coords_tma_rm <- coords_tma_rm[, .(lat = Y, lon = X), by = id_stop] #renomear colunas

# visualizar se estacoes estao corretas
coords_tma_rm_sf <- st_as_sf(coords_tma_rm, coords = c("lon", "lat"), crs = 4326)
mapview::mapview(coords_tma_rm_sf)

# criar lista de coordenadas para otp rotear areas de entorno
coords_list <- purrr::map2(as.numeric(coords_tma_rm$lon), as.numeric(coords_tma_rm$lat), c)

message('stations lat lon - ok')

#3. Criar areas no entorno das estacoes de transporte
#3.1. Criar funcao para gerar areas no entorno das estacoes de transporte
get_isochrone <- function(fromPlace, dist, walk_speed = 3.6, ...) {
  
  # modificar funcao do OTP para considerar metro por segundo
  x_speed <- walk_speed/3.6 # transformar velocidade por caminhada para de km/h para m/sed
  x_times <- dist/x_speed   # tempo a percorrer sera definidocom base na distancia definida
  iso <- otp_isochrone(fromPlace = fromPlace, 
                       cutoffSec = x_times,   
                       walkSpeed = x_speed,   
                       ...) #
  
  # adicionar distancia no resultado
  iso <- iso %>% mutate(distance = dist[length(dist):1])
  
}

# transformar funcao para criar areas no entorno das estacoes
get_isochrone_safe <- purrr::safely(get_isochrone)

#3.2. aplicar funcao para criar entorno das estacoes a partir do OTP
buffer <- lapply(coords_list, get_isochrone_safe, 
                 dist = 1000,
                 mode = "WALK",
                 otpcon = otp_rm,
                 walk_speed = 3.6)

# extrair feicoes do entorno
b <- map_depth(buffer, 1, function(x) x[[1]])

# juntar todas as feicoes e dissolver em unico arquivo georreferenciado
b_sf <- bind_rows(b) %>% as_tibble()%>% 
  st_sf(crs = 4326) %>% mutate(distance = as.character(distance)) %>%
  st_buffer(., 0) %>% st_union() 

# visualizar a area do entorno
mapview(b_sf)+mapview(coords_tma_rm_sf)

# salvar
write_rds(b_sf, './dados/rmb_buffer_2019.rds')
