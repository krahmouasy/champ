C ---------- predefined namlist check -------
C this file is auto generated, do not edit   
      subroutine p2nmcheck(p,v,ierr)
      character p*(*),v*(*)
      character lists(21)*(12)
      character vars(153)*(16)
      dimension iaptr(21),ieptr(21)
      data lists/'electrons','atoms','startend','general','jastrow',
     $ 'periodic','blocking_dmc','optgeo','vmc','forces',
     $ 'blocking_vmc','gradients','dmc','qmmm','optwf','pseudo',
     $ '3dgrid','properties','mstates','strech','ci'/
      data vars/'nelec','nup','nctype','natom','addghostype',
     $ 'nghostcent','idump','irstar','isite','icharged_atom','title',
     $ 'unit','mass','iperiodic','ibasis','nforce','nwftype','seed',
     $ 'ipr','pool','basis','pseudopot','i3dsplorb','i3dlagorb',
     $ 'scalecoef','ianalyt_lap','ijas','isc','nspin1','nspin2',
     $ 'ifock','norb','npoly','np','cutg','cutg_sim','cutg_big',
     $ 'cutg_sim_big','nstep','nblk','nblkeq','nconf_new','nconf',
     $ 'iforce_analy','iuse_zmat','alfgeo','izvzb','iroot_geo',
     $ 'imetro','deltar','deltat','delta','fbias','node_cutoff',
     $ 'enode_cutoff','istrech','alfstr','nwprod','itausec','nstep',
     $ 'nblk','nblkeq','nconf_new','nconf','ngradnts','igrdtype',
     $ 'delgrdxyz','delgrdbl','delgrdba','delgrdda','idmc','tau',
     $ 'etrial','nfprod','ipq','itau_eff','iacc_rej','icross',
     $ 'icuspg','idiv_v','icut_br','icut_e','icasula','node_cutoff',
     $ 'enode_cutoff','ibranch_elec','icircular','idrifdifgfunc',
     $ 'mode_dmc','iqmmm','ioptwf','idl_flag','ilbfgs_flag',
     $ 'ilbfgs_m','method','nopt_iter','ioptjas','ioptorb','ioptci',
     $ 'multiple_adiag','add_diag','ngrad_jas_blocks','nblk_max',
     $ 'nblk_ci','dl_alg','iorbprt','isample_cmat','istddev',
     $ 'limit_cmat','e_shift','save_blocks','force_blocks',
     $ 'iorbsample','iuse_trafo','iuse_orbeigv','ncore','nextorb',
     $ 'no_active','approx','approx_mix','energy_tol','sr_tau',
     $ 'sr_eps','sr_adiag','micro_iter_sr','dl_mom','lin_eps',
     $ 'lin_adiag','lin_nvec','lin_nvecx','lin_jdav','func_omega',
     $ 'omega','n_omegaf','n_omegat','sr_rescale','nloc','nquad',
     $ 'stepx','stepy','stepz','x0','y0','z0','xn','yn','zn','sample',
     $ 'print','iguiding','iefficiency','alfstr','iciprt'/
      data iaptr/1,3,7,11,26,32,39,44,49,56,60,65,71,90,91,137,139,
     $ 148,150,152,153/
      data ieptr/2,6,10,25,31,38,43,48,55,59,64,70,89,90,136,138,147,
     $ 149,151,152,153/
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
