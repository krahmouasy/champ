C ---------- predefined namlist check -------
C this file is auto generated, do not edit   
      subroutine p2nmcheck(p,v,ierr)
      character p*(*),v*(*)
      character lists(21)*(12)
      character vars(153)*(16)
      dimension iaptr(21),ieptr(21)
      data lists/'dmc','blocking_vmc','blocking_dmc','ci','startend',
     $ 'properties','mstates','vmc','pseudo','jastrow','forces',
     $ 'periodic','atoms','optgeo','strech','electrons','3dgrid',
     $ 'qmmm','optwf','general','gradients'/
      data vars/'idmc','tau','etrial','nfprod','ipq','itau_eff',
     $ 'iacc_rej','icross','icuspg','idiv_v','icut_br','icut_e',
     $ 'icasula','node_cutoff','enode_cutoff','ibranch_elec',
     $ 'icircular','idrifdifgfunc','mode_dmc','nstep','nblk','nblkeq',
     $ 'nconf_new','nconf','nstep','nblk','nblkeq','nconf_new',
     $ 'nconf','iciprt','idump','irstar','isite','icharged_atom',
     $ 'sample','print','iguiding','iefficiency','imetro','deltar',
     $ 'deltat','delta','fbias','node_cutoff','enode_cutoff','nloc',
     $ 'nquad','ianalyt_lap','ijas','isc','nspin1','nspin2','ifock',
     $ 'istrech','alfstr','nwprod','itausec','norb','npoly','np',
     $ 'cutg','cutg_sim','cutg_big','cutg_sim_big','nctype','natom',
     $ 'addghostype','nghostcent','iforce_analy','iuse_zmat','alfgeo',
     $ 'izvzb','iroot_geo','alfstr','nelec','nup','stepx','stepy',
     $ 'stepz','x0','y0','z0','xn','yn','zn','iqmmm','ioptwf',
     $ 'idl_flag','ilbfgs_flag','ilbfgs_m','method','nopt_iter',
     $ 'ioptjas','ioptorb','ioptci','multiple_adiag','add_diag',
     $ 'ngrad_jas_blocks','nblk_max','nblk_ci','dl_alg','iorbprt',
     $ 'isample_cmat','istddev','limit_cmat','e_shift','save_blocks',
     $ 'force_blocks','iorbsample','iuse_trafo','iuse_orbeigv',
     $ 'ncore','nextorb','no_active','approx','approx_mix',
     $ 'energy_tol','sr_tau','sr_eps','sr_adiag','micro_iter_sr',
     $ 'dl_mom','lin_eps','lin_adiag','lin_nvec','lin_nvecx',
     $ 'lin_jdav','func_omega','omega','n_omegaf','n_omegat',
     $ 'sr_rescale','title','unit','mass','iperiodic','ibasis',
     $ 'nforce','nwftype','seed','ipr','pool','basis','pseudopot',
     $ 'i3dsplorb','i3dlagorb','scalecoef','ngradnts','igrdtype',
     $ 'delgrdxyz','delgrdbl','delgrdba','delgrdda'/
      data iaptr/1,20,25,30,31,35,37,39,46,48,54,58,65,69,74,75,77,86,
     $ 87,133,148/
      data ieptr/19,24,29,30,34,36,38,45,47,53,57,64,68,73,74,76,85,
     $ 86,132,147,153/
      nlist=21
      ierr=0
      do i=1,nlist
       if(lists(i).eq.p) then
        do iv=iaptr(i),ieptr(i)
         if(vars(iv).eq.v) then
          return
         endif
        enddo
        ierr=1
        return
       endif
      enddo
      return
      end
