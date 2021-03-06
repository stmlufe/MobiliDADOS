#Passo-a-passo do calculo do PNB
#1. Instalar pacotes e definir diretorio 
#2. Calculo PNB


#1. Instalar pacotes e definir diretorio ----
#1.1. Instalar pacotes
install.packages('sf')
install.packages('dplyr')
install.packages('readr')
install.packages('openxlsx')
install.packages('pbapply')
install.packages('beepr')
install.packages('stringr')
install.packages('tidyr')


#1.2 Abrir pacotes
library(sf)
library(dplyr)
library(readr)
library(openxlsx)
library(mapview)
library(pbapply)
library(beepr)
library(stringr)
library(tidyr)

# 1.3. Defnir diretorio
setwd('/Users/mackook/Desktop/R/') #mac
setwd('E:/R/') #pc


##1.4. Criar tabela de referencia para capitais
#DF e Vitoria nao foram baixadas do Ciclomapa em funcao de erro do app
munis_df <- data.frame(code_muni = c(2927408, 3550308, 3304557, 2611606, 
                                     2304400, 5300108, 4106902,
                                     3106200, 1501402, 1100205, 1200401,
                                     1302603, 1400100, 1600303, 1721000, 2111300,
                                     2211001, 2408102, 2507507, 2704302, 2800308,
                                     3205309, 4205407, 4314902, 5002704,
                                     5103403, 5208707),
                       name_muni=c('salvador', 'sao paulo','rio de janeiro', 'recife',
                                   'fortaleza', 'distrito federal', 'curitiba', 
                                   'belo horizonte', 'belem', 'porto velho', 'rio branco', 
                                   'manaus', 'boa vista', 'macapa', 'palmas', 'sao luis',
                                   'teresina', 'natal', 'joao pessoa', 'maceio', 'aracaju', 
                                   'vitoria', 'florianopolis', 'porto alegre', 'campo grande', 
                                   'cuiaba', 'goiania'),
                       abrev_state=c('BA', 'SP', 'RJ', 'PE', 'CE', 'DF', 'PR', 'MG', 'PA', 'RO',
                                     'AC', 'AM', 'RR', 'AP', 'TO', 'MA', 'PI', 'RN', 'PB', 'AL',
                                     'SE', 'ES', 'SC', 'RS', 'MS', 'MT', 'GO'), 
                       espg = c(31984, 31983, 31983, 31985, 31984, 31983, 31982, 31983, 31982, 
                                31980, 31979, 31980, 31980, 31982, 31982, 31983, 31983,
                                31985, 31985, 31985, 31984, 31984, 31982, 31982, 31981,
                                31981, 31982),
                       sigla_muni = c("ssa", "spo", "rio", "rec", "for", "dis", "cur", 
                                      "bho", "bel", "por", "rbr", "man", "boa", "mac", 
                                      "pal", "sls", "ter", "nat", "joa", "mco", "ara", 
                                      "vit", "flo", "poa", "cam", "cui", "goi"))






#2. Calculo PNB ----
#2.1. Criar funcao para calculo do PNB

PNB  <- function(i){
  
  message(paste0('Ola, ', subset(munis_df, sigla_muni==i)$name_muni,'! =)', "\n"))
  
  #Abrir infraestrutura cicloviaria
  buf <- read_rds(paste0('./codigos/tt_isochrones-master/output/pnb/2019/', subset(munis_df, sigla_muni==i)$name_muni, '_network_buffer.rds'))   #buffer com distancia real
  buf <- st_transform(buf,  subset(munis_df, sigla_muni==i)$espg)
  buf <- buf %>% st_set_precision(1000000) %>% lwgeom::st_make_valid() #corrigir shapes que podem possuir algum defeito de feicao
  
  #Abrir setores censitarios
  setores <- read_rds(paste0('./dados/capitais/setores/rds/setores_', 
                             subset(munis_df, sigla_muni==i)$name_muni, '.rds' )) %>%
    rename(Cod_setor = code_tract) %>% 
    mutate(Ar_m2 = unclass(st_area(.)), Cod_setor = as.character(Cod_setor))
  setores <- st_transform(setores, 4326) #transforma projecao
  setores <- st_transform(setores,  subset(munis_df, sigla_muni==i)$espg) #transforma projecao
  setores <- st_buffer(setores,0)
  message(paste0('abriu e ajustou setores - ', subset(munis_df, sigla_muni==i)$name_muni,"\n"))
  
  #Abrir dados censitarios
  
  dados <- read_rds('./dados/IBGE/dados_setores/3_tabela_pais/dados_setores.rds') %>% 
    mutate(Cod_setor=as.character(Cod_setor))%>% filter(Cod_municipio==subset(munis_df, sigla_muni==i)$code_muni)
  message(paste0('abriu dados censitarios - ', subset(munis_df, sigla_muni==i)$name_muni,"\n"))
  
  #Juntar setores com dados censitarios
  dados_cid <- left_join(setores, dados, by = 'Cod_setor') %>% st_sf()
  #dados_cid <- st_transform(dados, 4326) #transforma projecao
  dados_cid <- st_transform(dados_cid, subset(munis_df, sigla_muni==i)$espg) #transforma projecao
  dados_cid <- dados_cid %>% st_set_precision(1000000) %>% lwgeom::st_make_valid() #corrigir shapes que podem possuir algum defeito de feicao
  message(paste0('setores e dados foram unidos - ', subset(munis_df, sigla_muni==i)$name_muni,"\n"))
  
  #Recortar setores pelo buffer
  setores_entorno <- st_intersection(dados_cid, buf) #recortar setores dentro da area de entorno das estacoes
  message(paste0('recortou setores no entorno - ', subset(munis_df, sigla_muni==i)$name_muni,"\n"))
  beep()
  
  #Calculo do total de cada variavel no entorno da infraestrutura cicloviaria
  setores_entorno <- setores_entorno %>%
    mutate(ar_int = unclass(st_area(.)), #cria area inserida no entorno da estacao
           rt = as.numeric(ar_int/Ar_m2)) %>% #cria proporcao entre area inserida no entorno da estacao e area total de cada 
    mutate_at(.vars = vars(Pop, DR_0_meio, DR_meio_1, DR_1_3, DR_3_mais, M_Negras , M_2SM), 
              funs(int = . * rt)) #criar variaveis proximas das estacoes
  
  total_entorno <- c((sum(setores_entorno$Pop_int, na.rm = TRUE)), 
                     (sum(setores_entorno$DR_0_meio_int, na.rm = TRUE)), 
                     (sum(setores_entorno$DR_meio_1_int, na.rm = TRUE)), 
                     (sum(setores_entorno$DR_1_3_int, na.rm = TRUE)), 
                     (sum(setores_entorno$DR_3_mais_int, na.rm = TRUE)), 
                     (sum(setores_entorno$M_Negras_int, na.rm = TRUE)), 
                     (sum(setores_entorno$M_2SM_int, na.rm = TRUE))) #Realizar a soma total de cada variavel
  
  #Calculo do total de cada variavel na cidade analisada
  total_cidade <- c((sum(dados_cid$Pop, na.rm = TRUE)), 
                    (sum(dados_cid$DR_0_meio, na.rm = TRUE)), 
                    (sum(dados_cid$DR_meio_1, na.rm = TRUE)), 
                    (sum(dados_cid$DR_1_3, na.rm = TRUE)), 
                    (sum(dados_cid$DR_3_mais, na.rm = TRUE)), 
                    (sum(dados_cid$M_Negras, na.rm = TRUE)), 
                    (sum(dados_cid$M_2SM, na.rm = TRUE))) #Realizar a soma total de cada variavel
  
  #Calculo do resultado final
  Resultados_pnb <-rbind(total_entorno, total_cidade, round(100*(total_entorno/total_cidade),0))
  row.names(Resultados_pnb)<- c("total_entorno","total_cidade", "resultado_%") #Nomeia as linhas da tabela criada
  colnames(Resultados_pnb)<- c("Pop", "DR_0_meio","DR_meio_1","DR_1_3","DR_3_mais", "M_Negras", "M_2SM") #Nomear as colunas da tabela criada
  print(Resultados_pnb) #Verfica tabela
  
  Resultados_pnb_final <- as.data.frame(t(Resultados_pnb))
  Resultados_pnb_final$cidade <- str_to_title(subset(munis_df, sigla_muni==i)$name_muni)
  print(Resultados_pnb_final) #Verfica tabela final
  
  write.xlsx(Resultados_pnb_final, paste0('./resultados/pnb/2019/network/', 
                                          subset(munis_df, sigla_muni==i)$name_muni, '_pnb_2019.xlsx'),
             header = T, col.names = TRUE, row.names = TRUE)#salvar resultado final
  
  beep()
  message(paste0('salvou resultados - ', subset(munis_df, code_muni==i)$name_muni,"\n"))
  beep()
  
}

#2.2. Aplicar funcao para calcular PNB nas capitais
#criar lista de codigos dos municipios
list_sigla_muni <- munis_df$sigla_muni

#aplicar funcao para calcular PNB para todas as capitais
start_time <- Sys.time() # horario de inicio da funcao

pblapply(list_sigla_muni, PNB) # aplicar fundao

end_time <- Sys.time() # horario de fim da funcao

#aplicar funcao para calcular PNB para uma capital
PNB("bho")

#3. Juntar em tabela unica para MobiliDADOS database

#3.1. criar tabela unica
#criar lista
files <- list.files(path = './resultados/pnb/2019/network',
                    pattern = "\\.xlsx$", full.names = TRUE)

ler <- lapply(files, read.xlsx)

#ler e juntar
juntos <- do.call("rbind", lapply(files, read.xlsx))

#salvar
write.xlsx(juntos, './resultados/pnb/2019/network/consolidado/resultados_capitais.xlsx')

#3.2 criar tabela para database
# abrir tabela
todos <- read.xlsx('./resultados/pnb/2019/network/consolidado/resultados_capitais.xlsx')
todos$cidade <- as.factor(todos$cidade) # transformar coluna de cidades em fator

todos_long <- gather(todos, variavel, valor, 2:4, factor_key=TRUE) # transfomar wide para long
write.xlsx(todos_long, './resultados/pnb/2019/network/consolidado/resultados_capitais_database.xlsx') # salvar
