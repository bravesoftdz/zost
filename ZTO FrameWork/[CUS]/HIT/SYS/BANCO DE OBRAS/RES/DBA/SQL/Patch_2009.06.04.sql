# CONFIGURE ABAIXO O NOME DO BANCO DE DADOS COLOCANDO-O ENTRE ASPAS NA
# ATRIBUI��O DA VARI�VEL E SEM ASPAS NO COMANDO "USE"
SET @BANCODEDADOS := 'BANCODEOBRAS3';
USE BANCODEOBRAS3;

# ==============================================================================
# O QUE EU ESTOU FAZENDO AQUI...
# CRIADA A FUN��O "FNC_GET_JUSTIFICATIVE_FROM_WORK"
# MODIFICADA A FUN��O "FNC_GET_ITEM_VALUE"
# MODIFICADA A FUN��O "FNC_GET_BRUTE_PROFIT" DEVIDO A ALTERA��ES EM "FNC_GET_ITEM_VALUE"
# MODIFICADA A FUN��O "FNC_GET_PROPOSAL_REAJUST_MULTIPLIER" DEVIDO A ALTERA��ES EM "FNC_GET_ITEM_VALUE"
# MODIFICADA A FUN��O "FNC_GET_PROPOSAL_VALUE" DEVIDO A ALTERA��ES EM "FNC_GET_ITEM_VALUE"
# AUMENTANDA A PRECIS�O DO CAMPO "FL_VALORUNITARIO" DA TABELA "EQUIPAMENTOS" (DECIMAL(12,4))
# AUMENTANDA A PRECIS�O DO CAMPO "FL_LUCROBRUTO" DA TABELA "EQUIPAMENTOS" (DECIMAL(12,4))
# AUMENTANDA A PRECIS�O DO CAMPO "FL_IPI" DA TABELA "EQUIPAMENTOS" (DECIMAL(12,4))
# AUMENTANDA A PRECIS�O DO CAMPO "FL_VALORUNITARIO" DA TABELA "EQUIPAMENTOSDOSITENS" (DECIMAL(12,4))
# AUMENTANDA A PRECIS�O DO CAMPO "FL_VALOR" DA TABELA "ICMS" (DECIMAL(12,4))
# ==============================================================================

# == VARIAVEIS TEMPORRIAS ======================================================
# A VARI�VEL "SYNCHRONIZING" � �TIL APENAS NO CLIENTE POIS L� PODE HAVER A��ES
# EM TABELAS GERADAS DURANTE UMA SINCRONIZA��O OU N�O. NO SERVIDOR, QUANDO
# "SERVERSIDE" = TRUE, ESTA VARI�VEL � IGNORADA POIS NO SERVIDOR ESTAREMOS
# SEMPRE SINCRONIZANDO

# O USO DESTAS VARI�VEIS AQUI S� � EFETIVO SE HOUVER MANIPUL��O DE DADOS NESTE
# SCRIPT. SERVERSIDE = TRUE � CONDI��O SUFICIENTE PARA DIZER QUE SE EST�
# SINCRONIZANDO NO SERVIDOR POIS O SERVIDOR N�O � ACESS�VEL DIRETAMENTE, APENAS
# VIA SINCRONIZ��O
SET @SYNCHRONIZING = FALSE;
SET @CURRENTLOGGEDUSER = 1;
SET @SERVERSIDE = TRUE;
SET @ADJUSTINGDB = TRUE;
SET FOREIGN_KEY_CHECKS = 0;
# ATEN��O: QUANDO FOREIGN_KEY_CHECKS EST� DESATIVADO NENHUMA FUN��O RELACIONADA
# A INTEGRIDADE REFERENCIAL SER� EXECUTADA A SABER: ONDELETE E ONUPDATE. SE SUA
# INTEN��O � EXCLUIR PROPOSITALMENTE ALGUNS REGISTROS A T�TULO DE LIMPEZA, ISSO
# DEVE SER FEITO QUANDO "FOREIGN_KEY_CHECKS = 1" DO CONTR�RIO O BANCO FICAR�
# INCONSISTENTE (REGISTROS �RF�OS)
# ==============================================================================

# == STORED PROCEDURES =========================================================
# ------------------------------------------------------------------------------
# FUN��O QUE RETORNA AS JUSTIFICATIVAS DE UMA OBRA PASSADA POR PAR�METRO
DROP FUNCTION IF EXISTS FNC_GET_JUSTIFICATIVE_FROM_WORK;
DELIMITER �
CREATE FUNCTION FNC_GET_JUSTIFICATIVE_FROM_WORK(ID INTEGER UNSIGNED)
RETURNS VARCHAR(400)
SQL SECURITY DEFINER
BEGIN
  DECLARE RESULTADO VARCHAR(400);

  SELECT GROUP_CONCAT(JUS.VA_JUSTIFICATIVA SEPARATOR ', ')
    INTO RESULTADO
    FROM JUSTIFICATIVASDASOBRAS JDO
    JOIN JUSTIFICATIVAS JUS USING (TI_JUSTIFICATIVAS_ID)
   WHERE JDO.IN_OBRAS_ID = ID;

  RETURN RESULTADO;
END; �
DELIMITER ;
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# ADI��O DE MAIS UM PAR�METRO PARA ARREDONDAR ANTES RETORNAR O VALOR DO ITEM. OS
# PAR�METROS QUE FAZIAM REFER�NCIA AO REAJUSTE DA PROPOSTA FORAM REMOVIDOS PARA
# MANTER A FUNCIONALIDADE UNICA DESTA FUN��O COMO SENDO: "RETORNAR O VALOR DO
# ITEM". SE O REAJUSTE DA PROPOSTA PRECISAR SER APLICADO, ISSO DEVE SER FEITO
# FORA DA FUN��O
DROP FUNCTION IF EXISTS FNC_GET_ITEM_VALUE;
DELIMITER �
CREATE FUNCTION FNC_GET_ITEM_VALUE(ITEMID INTEGER UNSIGNED
                                  ,UNITARY BOOLEAN
                                  ,AUTODETECTEXCHANGE BOOLEAN
                                  ,EXCHANGEVALUES VARCHAR(39)
                                  ,DECIMALPLACES TINYINT)
RETURNS DOUBLE
SQL SECURITY DEFINER
BEGIN
    DECLARE ITEM_VALUE DOUBLE DEFAULT 0;
    DECLARE ICMS_MULTIPLIER DOUBLE DEFAULT 1;
    DECLARE REAJUSTE DOUBLE DEFAULT 1;
    DECLARE QUANTIDADE SMALLINT UNSIGNED;

    SET ICMS_MULTIPLIER := FNC_GET_ICMS_MULTIPLIER(FNC_GET_WORK_FROM_PROPOSAL(FNC_GET_PROPOSAL_FROM_ITEM(ITEMID)));

    IF DECIMALPLACES > -1 THEN

        SELECT SUM(ROUND(EDI.FL_VALORUNITARIO * ICMS_MULTIPLIER,DECIMALPLACES))
             , ITE.FL_DESCONTOPERC
             , ITE.SM_QUANTIDADE
          INTO ITEM_VALUE
             , REAJUSTE
             , QUANTIDADE
          FROM EQUIPAMENTOSDOSITENS EDI
          JOIN ITENS ITE USING (IN_ITENS_ID)
         WHERE EDI.IN_ITENS_ID = ITEMID;

    ELSE

        SELECT SUM(EDI.FL_VALORUNITARIO * ICMS_MULTIPLIER)
             , ITE.FL_DESCONTOPERC
             , ITE.SM_QUANTIDADE
          INTO ITEM_VALUE
             , REAJUSTE
             , QUANTIDADE
          FROM EQUIPAMENTOSDOSITENS EDI
          JOIN ITENS ITE USING (IN_ITENS_ID)
         WHERE EDI.IN_ITENS_ID = ITEMID;

    END IF;

    IF NOT UNITARY THEN
        IF DECIMALPLACES > -1 THEN
            # TIVE DE USAR CAST AQUI POIS O USO DO ROUND SOZINHO N�O ESTAVA ADIANTANDO
            SET ITEM_VALUE := ROUND(CAST(ITEM_VALUE * FNC_GET_REAJUST_MULTIPLIER(REAJUSTE) AS DECIMAL(12,4)),DECIMALPLACES) * QUANTIDADE;
        ELSE
            # SERIA PRECISO USAR CAST AQUI TAMB�M?
            SET ITEM_VALUE := ITEM_VALUE * FNC_GET_REAJUST_MULTIPLIER(REAJUSTE) * QUANTIDADE;
        END IF;
    END IF;

    # PODE SER NECESS�RIO USAR CAST ABAIXO
    IF AUTODETECTEXCHANGE THEN
        IF DECIMALPLACES > -1 THEN
            RETURN ROUND(ITEM_VALUE * FNC_GET_EXCHANGE_MULTIPLIER(ITEMID,NULL),DECIMALPLACES);
        ELSE
            RETURN ITEM_VALUE * FNC_GET_EXCHANGE_MULTIPLIER(ITEMID,NULL);
        END IF;
    ELSE
        IF NOT EXCHANGEVALUES IS NULL THEN
            IF DECIMALPLACES > -1 THEN
                RETURN ROUND(ITEM_VALUE * FNC_GET_EXCHANGE_MULTIPLIER(ITEMID,EXCHANGEVALUES),DECIMALPLACES);
            ELSE
                RETURN ITEM_VALUE * FNC_GET_EXCHANGE_MULTIPLIER(ITEMID,EXCHANGEVALUES);
            END IF;
        ELSE
            RETURN ITEM_VALUE;
        END IF;
    END IF;
END; �
DELIMITER ;
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# ESTA FUN��O TEVE DE SER ALTERADA INTERNAMENTE DEVIDO A ALTERA��O DA FUN��O
# "FNC_GET_ITEM_VALUE", SEU COMPORTAMENTO ENTRETANTO N�O FOI ALTERADO
DROP FUNCTION IF EXISTS FNC_GET_BRUTE_PROFIT;
DELIMITER �
CREATE FUNCTION FNC_GET_BRUTE_PROFIT(ITEMID INTEGER UNSIGNED)
RETURNS DOUBLE
BEGIN
	DECLARE LUCROSOMADOS DOUBLE;
	DECLARE REAJUSTE DOUBLE;
	DECLARE ICMS DOUBLE;
	DECLARE IDOBRA INTEGER UNSIGNED;

	SELECT OBR.IN_OBRAS_ID
	  INTO IDOBRA
	  FROM OBRAS OBR
	  JOIN PROPOSTAS PRO USING (IN_OBRAS_ID)
	  JOIN ITENS ITE USING (IN_PROPOSTAS_ID)
	 WHERE ITE.IN_ITENS_ID = ITEMID;

	 SET ICMS := FNC_GET_ICMS_MULTIPLIER(IDOBRA);

	   SELECT ITE.FL_DESCONTOPERC
	        , SUM(EDI.FL_VALORUNITARIO * EDI.FL_LUCROBRUTO / 100) * ICMS
  	   INTO REAJUSTE, LUCROSOMADOS
	     FROM EQUIPAMENTOSDOSITENS EDI
	     JOIN ITENS ITE USING (IN_ITENS_ID)
	     JOIN PROPOSTAS PRO USING (IN_PROPOSTAS_ID)
  	   JOIN OBRAS OBR USING (IN_OBRAS_ID)
	    WHERE EDI.IN_ITENS_ID = ITEMID
	 GROUP BY ITE.IN_ITENS_ID;

	 RETURN LUCROSOMADOS / FNC_GET_ITEM_VALUE(ITEMID,TRUE,FALSE,NULL,-1) * 100 + REAJUSTE;
END; �
DELIMITER ;
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# ESTA FUN��O TEVE DE SER ALTERADA INTERNAMENTE DEVIDO A ALTERA��O DA FUN��O
# "FNC_GET_ITEM_VALUE", SEU COMPORTAMENTO ENTRETANTO N�O FOI ALTERADO
DROP FUNCTION IF EXISTS FNC_GET_PROPOSAL_REAJUST_MULTIPLIER;
DELIMITER �
CREATE FUNCTION FNC_GET_PROPOSAL_REAJUST_MULTIPLIER(PROPOSALID INTEGER UNSIGNED)
RETURNS DOUBLE
BEGIN
	DECLARE DESCONTOPERC DOUBLE;
	DECLARE DESCONTOVAL DOUBLE;
    DECLARE VALORDAPROPOSTA DOUBLE;

    # OBTENDO O VALOR DA PROPOSTA SEM REAJUSTES
    SELECT SUM(FNC_GET_ITEM_VALUE(IN_ITENS_ID,FALSE,TRUE,NULL,-1))
      INTO VALORDAPROPOSTA
      FROM ITENS
     WHERE IN_PROPOSTAS_ID = PROPOSALID;

    # OBTENDO OS REAJUSTES DA PROPOSTA
    SELECT FL_DESCONTOPERC
         , FL_DESCONTOVAL
      INTO DESCONTOPERC
         , DESCONTOVAL
      FROM PROPOSTAS
     WHERE IN_PROPOSTAS_ID = PROPOSALID;

    IF NOT DESCONTOVAL IS NULL THEN

        # FNC_GET_REAJUST_MULTIPLIER USA COMO PARAMETRO UM VALOR EM PERCENTUAL E
        # RETORNA UM MULTIPLICADOR. POR ISSO FOI PRECISO MULTIPLICAR O VALOR POR
        # 100 DE FORMA QUE A FUN��O PUDESSE SER USADA
        RETURN FNC_GET_REAJUST_MULTIPLIER(DESCONTOVAL / VALORDAPROPOSTA * 100);

    ELSE

        RETURN FNC_GET_REAJUST_MULTIPLIER(DESCONTOPERC);

    END IF;

END; �
DELIMITER ;
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# ESTA FUN��O TEVE DE SER ALTERADA INTERNAMENTE DEVIDO A ALTERA��O DA FUN��O
# "FNC_GET_ITEM_VALUE", SEU COMPORTAMENTO ENTRETANTO N�O FOI ALTERADO
DROP FUNCTION IF EXISTS FNC_GET_PROPOSAL_VALUE;
DELIMITER �
CREATE FUNCTION FNC_GET_PROPOSAL_VALUE(IDPROPOSAL INTEGER UNSIGNED
                                      ,SUBTOTAL BOOLEAN
                                      ,AUTODETECTEXCHANGE BOOLEAN
                                      ,EXCHANGEVALUES VARCHAR(39)
                                      ,DECIMALPLACES TINYINT)
RETURNS DOUBLE
BEGIN
	DECLARE VALOR_PROPOSTA DOUBLE;
    DECLARE PROPOSALREAJUST DOUBLE;
    DECLARE USEPROPOSALREAJUST BOOLEAN;

	# OS VALORES OBTIDOS DOS ITENS COM "FNC_GET_ITEM_VALUE" S�O INTEGRAIS (COM
    # TODAS AS CASAS DECIMAIS), LOGO O SEU SOMAT�RIO GERA UM VALOR PRECISO,
    # ENTRETANTO NAS PROPOSTAS GERADAS OS VALORES DE CADA ITEM S�O APRESENTADOS
    # ARREDONDADOS PARA 2 CASAS DECIMAIS E O VALOR FINAL DA PROPOSTA FAZ O
    # C�LCULO SOMANDO OS VALORES REAIS DE CADA UM DOS ITENS (SEM ARREDONDAMENTO)
    # O QUE CAUSAVA UM DISCREP�NCIA ENTRE O SOMAT�RIO DO QUE � APRESENTADO E O
    # VALOR FINAL DA PROPOSTA EXIBIDO. A FIM DE RESOLVER ESTA DISCREP�NCIA, MAIS
    # UM PAR�METRO FOI INCLU�DO NESTA FUN��O (FNC_GET_PROPOSAL_VALUE) PARA
    # INFORMAR SE DEVEMOS ARREDONDAR O VALOR DE CADA ITEM ANTES DE SOMAR E PARA
    # QUANTAS CASAS DECIMAIS ISSO DEVE SER FEITO. ESTA N�O � A FORMA QUE RETORNA
    # RESULTADOS MAIS PRECISOS, MAS � A QUE RETORNA OS VALORES MAIS COERENTES
    # PARA EXIBI��O. O CORRETO SERIA SOMAR TODOS OS VALORES DE FORMA INTEGRAL
    # PARA APENAS NO FINAL REALIZAR O ARREDONDAMENTO.

    # OBTENDO O REAJUSTE DA PROPOSTA
    SET PROPOSALREAJUST := FNC_GET_PROPOSAL_REAJUST_MULTIPLIER(IDPROPOSAL);
    SET USEPROPOSALREAJUST := PROPOSALREAJUST <> 1 AND NOT SUBTOTAL;

    SELECT SUM(FNC_GET_ITEM_VALUE(IN_ITENS_ID,FALSE,AUTODETECTEXCHANGE,EXCHANGEVALUES,DECIMALPLACES))
      INTO VALOR_PROPOSTA
      FROM ITENS
     WHERE IN_PROPOSTAS_ID = IDPROPOSAL;

    IF USEPROPOSALREAJUST THEN
        SET VALOR_PROPOSTA := VALOR_PROPOSTA * PROPOSALREAJUST;
    END IF;

    IF DECIMALPLACES > -1 THEN
        SET VALOR_PROPOSTA := ROUND(VALOR_PROPOSTA,DECIMALPLACES);
    END IF;

	RETURN VALOR_PROPOSTA;

END; �
DELIMITER ;
# ------------------------------------------------------------------------------

# == VIEWS =====================================================================

# ==============================================================================
# A PARTIR DESTE PONTO TODAS AS A��ES FAR�O USO DA INTEGRIDADE REFERENCIAL, O
# QUE SIGNIFICA QUE OS DADOS TEM DE ESTAR CORRETOS
SET FOREIGN_KEY_CHECKS = 1;
# ==============================================================================
# AUMENTANDO A PRECIS�O DO VALORES EM ALGUMAS TABELAS.
ALTER TABLE EQUIPAMENTOS
            MODIFY COLUMN FL_VALORUNITARIO DECIMAL(12,4) NOT NULL
          , MODIFY COLUMN FL_LUCROBRUTO DECIMAL(12,4) NOT NULL
          , MODIFY COLUMN FL_IPI DECIMAL(12,4) NOT NULL;

ALTER TABLE EQUIPAMENTOSDOSITENS
            MODIFY COLUMN FL_VALORUNITARIO DECIMAL(12,4) NOT NULL
          , MODIFY COLUMN FL_LUCROBRUTO DECIMAL(12,4) NOT NULL;

ALTER TABLE ICMS
            MODIFY COLUMN FL_VALOR DECIMAL(12,4) NOT NULL;

ALTER TABLE OBRAS
            MODIFY COLUMN FL_ICMS DECIMAL(12,4) NOT NULL;

ALTER TABLE PROPOSTAS
            MODIFY COLUMN FL_DESCONTOPERC DECIMAL(12,4) DEFAULT NULL
          , MODIFY COLUMN FL_DESCONTOVAL DECIMAL(12,4) DEFAULT NULL;

ALTER TABLE ITENS
            MODIFY COLUMN FL_CAPACIDADE DECIMAL(12,4) NOT NULL
          , MODIFY COLUMN FL_DESCONTOPERC DECIMAL(12,4) DEFAULT 0;

 # ==============================================================================